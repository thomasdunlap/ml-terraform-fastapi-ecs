import joblib
import pandas as pd
import numpy as np
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestRegressor
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler


# Read the data
df = pd.read_csv("data.csv")

# Prepare the data
# Note: If we don't convert our Pandas dataframes to Numpy, our model will
#       always expect to be fitted with a Pandas dataframe. This means that the
#       Pandas package will be a requirement wherever we run our model, even
#       when we only use it to predict something.
X = df[["location", "size", "bedrooms"]].to_numpy()
y = df[["price"]].to_numpy()

# Create a preprocessing step
preprocessing = ColumnTransformer([
    ("encoder", OneHotEncoder(), [0]),  # encode the location
    ("scaler", StandardScaler(), [1-2]),  # scale the other features
])

# Create our pipeline
model = Pipeline([
    ("preprocessing", preprocessing),
    ("regressor", RandomForestRegressor()),
])

# Fit our model
model.fit(X, y)

# Save our model to disk
joblib.dump(model, "../app/models/sota_model.joblib")

