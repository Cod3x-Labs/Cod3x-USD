import pandas as pd
import matplotlib.pyplot as plt

log = False

# Load the CSV file
data = pd.read_csv("datas/output.csv")

# Filter the data for the specified asset
asset_data = data[data["asset"] == "0x1af7f588a501ea2b5bb3feefa744892aa2cf00e6"].copy()

# Convert the timestamp to datetime and the rates to float
asset_data["timestamp"] = pd.to_datetime(asset_data["timestamp"], unit="s")
asset_data["currentVariableBorrowRate"] = asset_data["currentVariableBorrowRate"].astype(float)
asset_data["stablePoolBalance"] = asset_data["stablePoolBalance"].astype(float)

# Create a figure with two subplots
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8), sharex=True)

# Upper subplot: currentVariableBorrowRate
ax1.plot(asset_data["timestamp"], asset_data["currentVariableBorrowRate"] / 1e25, label="currentVariableBorrowRate")
ax1.set_title("Rates over time for cdxUSD (0x1af7f588a501ea2b5bb3feefa744892aa2cf00e6)")
ax1.set_ylabel("Rates (in %)")
if log : 
    ax1.set_yscale('log')  # Set y-axis to log scale
ax1.legend()
ax1.grid(True)

# Lower subplot: stablePoolBalance
ax2.plot(asset_data["timestamp"], asset_data["stablePoolBalance"] / 1e25, color='green', label="stablePoolBalance")
ax2.set_xlabel("Timestamp")
ax2.set_ylabel("Stable Pool balance cdxUSD (in %)")
if log : 
    ax2.set_yscale('log')  # Set y-axis to log scale
ax2.legend()
ax2.grid(True)

plt.tight_layout()
plt.savefig('datas/rates_over_time.png')
