from fastapi import FastAPI
import joblib

app = FastAPI()
model = joblib.load("app/models/sota_model.joblib")

@app.get("/")
def read_root():
    return {"API status": "Tom is great!"}

@app.post("/predict/")
def predict_price(location, size, bedrooms):
    example = [location, size, bedrooms]
    price = model.predict([example])[0]
    return {"prediction": int(price)}


