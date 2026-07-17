import json
import uuid
from datetime import datetime, timezone
from fastapi import FastAPI, UploadFile, File, HTTPException
from groq import Groq
from supabase import create_client, Client

app = FastAPI(title="EHR API Engine - Supabase Integrated")

# ==========================================
# 1. KONFIGURASI API KEYS
# ==========================================
# Ganti API Key di bawah ini dengan milik Anda yang valid jika diperlukan
GROQ_API_KEY = "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"
groq_client = Groq(api_key=GROQ_API_KEY)

# Silakan isi dengan URL dan Anon Key proyek Supabase Anda sendiri
SUPABASE_URL = "YOUR_SUPABASE_URL" 
SUPABASE_KEY = "YOUR_SUPABASE_ANON_KEY" 
supabase_client: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

print("🚀 API EHR dengan Integrasi Supabase Siap Melayani Aplikasi Mobile!")

# ==========================================
# 2. ENDPOINT UNTUK APLIKASI MOBILE
# ==========================================
@app.post("/api/v1/transcribe-and-save")
async def transcribe_and_save(file: UploadFile = File(...)):
    generated_id = str(uuid.uuid4())
    current_time_rfc = datetime.now(timezone.utc).astimezone().isoformat()
    
    # Membaca file audio yang dikirim dari aplikasi mobile
    file_bytes = await file.read()
    
    # A. Proses Audio ke Teks via Groq Whisper Cloud
    try:
        transcription = groq_client.audio.transcriptions.create(
            file=(file.filename, file_bytes, file.content_type),
            model="whisper-large-v3", 
            language="id",            
            response_format="json"
        )
        teks_mentah = transcription.text
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Gagal memproses Audio STT: {str(e)}")

    # B. Ekstraksi Informasi Medis via Groq Llama 3.1 (JSON Mode Resmi)
    prompt = f"""
    Kamu adalah sistem AI ekstraksi data klinis rekam medis (EHR Engine). 
    Tugasmu mengekstrak data dari teks suara bidan menjadi objek JSON terstruktur.

    Format output JSON harus tepat memiliki struktur seperti ini:
    {{
      "age_years": integer,
      "systolic_bp_mmhg": integer,
      "diastolic_bp_mmhg": integer,
      "blood_sugar": {{ "value": integer, "unit": "mg/dL" }},
      "body_temperature": {{ "value": float, "unit": "°C" }},
      "bmi_kg_m2": float,
      "previous_complications": boolean,
      "preexisting_diabetes": boolean,
      "gestational_diabetes": boolean,
      "mental_health_indicator": string,
      "heart_rate_bpm": integer
    }}

    Aturan Mutlak:
    1. Konversi kata konfirmasi seperti "ada", "ya", "positif" menjadi true, dan "tidak ada", "negatif" menjadi false.
    2. Default nilai angka ke 0 dan boolean ke false jika parameter tidak disebutkan sama sekali di dalam teks.

    Teks Mentah Hasil Rekaman Bidan: "{teks_mentah}"
    """
    
    try:
        completion = groq_client.chat.completions.create(
            model="llama-3.1-8b-instant",
            messages=[{"role": "user", "content": prompt}],
            temperature=0.0,
            response_format={"type": "json_object"} # Mengunci output murni JSON valid
        )
        data_terstruktur = json.loads(completion.choices[0].message.content.strip())
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Gagal melakukan Ekstraksi AI Llama: {str(e)}")

    # C. Mapping Data & Insert ke Supabase Database
    db_data = {
        "id": generated_id,
        "measured_at": current_time_rfc,
        "teks_mentah": teks_mentah,
        "age_years": data_terstruktur.get("age_years", 0),
        "systolic_bp": data_terstruktur.get("systolic_bp_mmhg", 0),
        "diastolic_bp": data_terstruktur.get("diastolic_bp_mmhg", 0),
        "blood_sugar_value": data_terstruktur.get("blood_sugar", {}).get("value", 0),
        "blood_sugar_unit": data_terstruktur.get("blood_sugar", {}).get("unit", "mg/dL"),
        "body_temperature_value": data_terstruktur.get("body_temperature", {}).get("value", 0.0),
        "body_temperature_unit": data_terstruktur.get("body_temperature", {}).get("unit", "°C"),
        "bmi": data_terstruktur.get("bmi_kg_m2", 0.0),
        "mental_health": data_terstruktur.get("mental_health_indicator", "Normal"),
        "heart_rate": data_terstruktur.get("heart_rate_bpm", 0),
        "previous_complications": data_terstruktur.get("previous_complications", False),
        "preexisting_diabetes": data_terstruktur.get("preexisting_diabetes", False),
        "gestational_diabetes": data_terstruktur.get("gestational_diabetes", False)
    }

    try:
        response = supabase_client.table("rekam_medis").insert(db_data).execute()
    except Exception as db_err:
        raise HTTPException(status_code=500, detail=f"Gagal menyimpan ke Supabase: {str(db_err)}")

    # D. Kembalikan Response Sukses ke Aplikasi Mobile
    return {
        "status": "success",
        "message": "Data berhasil diproses AI dan disimpan ke database Supabase",
        "data_id": generated_id,
        "extracted_content": db_data
    }
