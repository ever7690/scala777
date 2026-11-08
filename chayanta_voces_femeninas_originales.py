# Chayanta - voces femeninas ficticias, sin suplantar personas privadas.
# Dependencias y modelos se instalan en el workflow; no altera el original.
import os, sys, re, json, ast, math, asyncio, zipfile, subprocess, shutil
from pathlib import Path
import numpy as np
import scipy.signal as signal
import soundfile as sf
import torch
from transformers import VitsModel, AutoTokenizer
from huggingface_hub import hf_hub_download
from scipy.signal import resample_poly
import edge_tts
from math import gcd

torch.set_num_threads(3)
BASE=Path.cwd()
DEST=BASE/"CHAYANTA_VOCES_FEMENINAS"
DEST.mkdir(exist_ok=True)
QUH="facebook/mms-tts-quh"
FOUT="CHAYANTA_DOS_VOCES_FEMENINAS_SAPITOS"
scene_nb=json.loads((BASE/"CHAYANTA_DOS_VOCES_SAPITOS_COLAB.ipynb").read_text(encoding="utf-8"))
scene_code="".join(scene_nb["cells"][1]["source"])
scene_ast=ast.parse(scene_code)
for node in scene_ast.body:
    if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=="ESCENAS" for t in node.targets):
        SCENES=ast.literal_eval(node.value)
        break
else: raise RuntimeError("No se encontraron escenas")
assert len(SCENES)==44

async def make_reference(voice,text,dest,rate,pitch):
    c=edge_tts.Communicate(text,voice=voice,rate=rate,pitch=pitch)
    await c.save(str(dest))

print("① Generando referencias de voz femeninas sintéticas...",flush=True)
async def refs():
    await make_reference("es-BO-SofiaNeural",
        "En el pueblo de Chayanta una abuelita cuenta un antiguo relato. "
        "La tierra está seca y los cultivos esperan la llegada de la lluvia. "
        "Mi pequeña nieta Casiana, escucha con atención el canto de los sapitos. "
        "Cada voz de la naturaleza nos enseña a cuidar la vida.",
        DEST/"adulta_sintetica.mp3","-20%","-16Hz")
    await make_reference("en-US-AnaNeural",
        "Hello grandma, I am Casiana. I want to hear your beautiful story about the rain. "
        "Look at the mountains and the little toads by the river. "
        "Will it rain today? I love listening to the toads as they sing.",
        DEST/"infantil_sintetica.mp3","-8%","+0Hz")
asyncio.run(refs())

def to_wav(mp3,wav):
    subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-y","-i",str(mp3),
                    "-ac","1","-ar","24000",str(wav)],check=True)
to_wav(DEST/"adulta_sintetica.mp3",DEST/"adulta_sintetica.wav")
to_wav(DEST/"infantil_sintetica.mp3",DEST/"infantil_sintetica.wav")

print("② Cargando motor quechua sudboliviano y convertidor OpenVoice...",flush=True)
tok=AutoTokenizer.from_pretrained(QUH)
tts=VitsModel.from_pretrained(QUH).eval()
rate=int(tts.config.sampling_rate)

ov_path=BASE/"OpenVoice"/"openvoice"/"api.py"
assert ov_path.is_file()
s=ov_path.read_text(encoding="utf-8")
assert "if kwargs.get('enable_watermark', True):" in s
ov_path.write_text(s.replace("if kwargs.get('enable_watermark', True):","if False:"),encoding="utf-8")
sys.path.insert(0,str(BASE/"OpenVoice"))
from openvoice.api import ToneColorConverter
cfg=hf_hub_download("myshell-ai/OpenVoiceV2",filename="converter/config.json")
ckpt=hf_hub_download("myshell-ai/OpenVoiceV2",filename="converter/checkpoint.pth")
converter=ToneColorConverter(cfg,device="cpu")
converter.load_ckpt(ckpt)
emb_adulta=converter.extract_se(str(DEST/"adulta_sintetica.wav"))
emb_nina=converter.extract_se(str(DEST/"infantil_sintetica.wav"))

def synth(text,role):
    tts.speaking_rate = 0.74 if role in ("romaldina","narradora") else 0.87
    inp=tok(text,return_tensors="pt")
    with torch.no_grad():
        y=tts(**inp).waveform.squeeze().cpu().float().numpy()
    assert y.size>0 and np.isfinite(y).all()
    return y.astype(np.float32)

# Una muestra real del idioma original para extraer el timbre de origen.
sf.write(str(DEST/"_mms_origen.wav"),synth(
    "Casianaqa awichanwan kuska kawsakuq karqa. Jamp'atuchakuna parata mañakunku.",
    "narradora"),rate)
emb_origen=converter.extract_se(str(DEST/"_mms_origen.wav"))

def convert(y,role,i):
    if role not in ("narradora","romaldina","casiana"):
        return y
    temp_in=DEST/f"origen_{i:03d}.wav"
    temp_out=DEST/f"convertido_{i:03d}.wav"
    sf.write(str(temp_in),y,rate)
    target=emb_nina if role=="casiana" else emb_adulta
    converter.convert(str(temp_in),emb_origen,target,
                      output_path=str(temp_out),message="Chayanta")
    data,sr=sf.read(str(temp_out),dtype="float32")
    if data.ndim>1:data=data.mean(axis=1)
    if sr!=rate:
        d=gcd(sr,rate)
        data=resample_poly(data,rate//d,sr//d).astype(np.float32)
    temp_in.unlink(missing_ok=True);temp_out.unlink(missing_ok=True)
    assert len(data)>int(0.2*rate) and np.isfinite(data).all()
    return data.astype(np.float32)

rng=np.random.default_rng(20261108)
def silence(t):return np.zeros(int(t*rate),dtype=np.float32)
def croar():
    t=np.arange(int(rate*.44))/rate
    freq=180-70*t/.44 + 18*np.sin(2*np.pi*9*t)
    phase=2*np.pi*np.cumsum(freq)/rate
    return ((.14*np.sin(phase)+.045*np.sin(phase*2))*np.sin(np.pi*t/.44)**2).astype(np.float32)

parts=[]; examples={}
print("③ Narrando las 44 escenas y convirtiendo el timbre...",flush=True)
for i,(role,txt) in enumerate(SCENES,1):
    sentences=re.split(r"(?<=[.!?])\s+",txt.strip())
    chunks=[]; current=""
    for sentence in sentences:
        if len(current+" "+sentence)>155 and current:
            chunks.append(current);current=sentence
        else:current=(current+" "+sentence).strip()
    if current:chunks.append(current)
    # Resguardar que las palabras no superen el contexto del modelo.
    y=np.concatenate([p for chunk in chunks for p in (synth(chunk,role),silence(.16))])
    y=convert(y,role,i)
    if role in ("romaldina","casiana") and role not in examples:
        examples[role]=y.copy()
    if role.startswith("sapito") or role=="sapitos_coro":
        y=np.concatenate((croar(),silence(.10),y))
    peak=np.max(np.abs(y)) if len(y) else 0
    if peak>0:y=np.clip(y*(.87/max(.87,peak)),-.95,.95)
    parts.extend((y,silence(.55)))
    if i%5==0 or i==44:print("   ESCENA",i,"/44",flush=True)

whole=np.concatenate(parts)
# Los efectos de lluvia entran en las escenas finales (muestra artística).
rain_from=2*(29-1)
start=sum(len(p) for p in parts[:rain_from])
n=len(whole)-start
if n>0:
    noise=rng.normal(0,.05,n).astype(np.float32)
    noise=signal.lfilter([.04],[1,-.98],noise).astype(np.float32)
    noise=noise/max(.0001,float(np.max(abs(noise))))
    ramp=np.minimum(1,np.arange(n)/max(1,rate*4))*np.minimum(1,np.arange(n)[::-1]/max(1,rate*4))
    whole[start:]+=noise*ramp*.032
whole=np.clip(whole,-.96,.96).astype(np.float32)

wav=DEST/(FOUT+".wav");mp3=DEST/(FOUT+".mp3")
sf.write(str(wav),whole,rate)
def encode(source,dest):
    subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-y",
        "-i",str(source),"-codec:a","libmp3lame","-b:a","192k",str(dest)],check=True)
encode(wav,mp3)
for role,nm in [("romaldina","MUESTRA_ROMALDINA_FEMENINA.mp3"),
                ("casiana","MUESTRA_CASIANA_FEMENINA.mp3")]:
    temp=DEST/(role+".wav")
    sf.write(str(temp),examples[role],rate)
    encode(temp,DEST/nm)
    temp.unlink()

(DEST/"CUENTO_QUECHUA_Y_PERSONAJES.txt").write_text(
    "\n\n".join("["+r+"] "+t for r,t in SCENES),encoding="utf-8")
(DEST/"LIMITACIONES_Y_LICENCIA.txt").write_text(
    "VOCES: perfiles femeninos ficticios convertidos por OpenVoice V2 "
    "a partir de voces sintéticas autorizadas para TTS. "
    "No se clonaron voces de Graciela Choque ni de Zaraí Llusco, "
    "ni de ninguna persona privada. "
    "El texto en quechua sudboliviano usa Meta MMS-TTS-quh, "
    "licencia CC BY-NC 4.0: SOLO USO NO COMERCIAL. "
    "La pronunciación y la percepción de género/edad de las voces "
    "NO se han validado con un hablante nativo. "
    "Los sapitos y la lluvia son efectos sintéticos.",encoding="utf-8")
zipfile_path=DEST/(FOUT+".zip")
with zipfile.ZipFile(zipfile_path,"w",zipfile.ZIP_DEFLATED) as z:
    for p in (mp3,wav,DEST/"MUESTRA_ROMALDINA_FEMENINA.mp3",
              DEST/"MUESTRA_CASIANA_FEMENINA.mp3",
              DEST/"CUENTO_QUECHUA_Y_PERSONAJES.txt",
              DEST/"LIMITACIONES_Y_LICENCIA.txt"):
        assert p.exists() and p.stat().st_size>100
        z.write(p,arcname=p.name)
with zipfile.ZipFile(zipfile_path) as z: assert z.testzip() is None
print("MP3_FEMENINO_VERIFICADO",mp3,mp3.stat().st_size,flush=True)
print("DURACION_SEGUNDOS",len(whole)/rate,flush=True)
print("PAQUETE_ZIP_VERIFICADO",zipfile_path,flush=True)
