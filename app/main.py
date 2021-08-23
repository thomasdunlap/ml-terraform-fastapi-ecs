from fastapi import FastAPI, Query
import joblib

app = FastAPI()
model = joblib.load("app/models/sota_model.joblib")

@app.get("/")
def read_root():
    return {"API status": "If you can see this, it's working!"}

@app.post("/predict/")
def predict_price(
    location: str = Query(..., description="Location", min_length=1),
    size: float = Query(..., description="Size (in meters squared)", ge=10.0),
    bedrooms: int = Query(2, description="Number of bedrooms", ge=0, le=50)
    ):
    
    example = [location, size, bedrooms]
    price = model.predict([example])[0]
    return {"prediction": int(price)}


