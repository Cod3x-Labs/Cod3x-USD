import pandas as pd
import matplotlib.pyplot as plt

log = False

# Load the CSV file
data = pd.read_csv("datas/output.csv")

# Filter the data for the specified asset
asset_data = data[data["asset"] == "0x13aa49bac059d709dd0a18d6bb63290076a702d7"].copy()

# Convert the timestamp to datetime and the rates to float
asset_data["timestamp"] = pd.to_datetime(asset_data["timestamp"], unit="s")
asset_data["currentVariableBorrowRate"] = asset_data["currentVariableBorrowRate"].astype(float)
asset_data["currentLiquidityRate"] = asset_data["currentLiquidityRate"].astype(float)
asset_data["utilizationRate"] = asset_data["utilizationRate"].astype(float)

# Create a figure with two subplots
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8), sharex=True)

# Upper subplot: currentVariableBorrowRate and currentLiquidityRate
ax1.plot(asset_data["timestamp"], asset_data["currentVariableBorrowRate"] / 1e25, label="currentVariableBorrowRate")
ax1.plot(asset_data["timestamp"], asset_data["currentLiquidityRate"] / 1e25, color='red', label="currentLiquidityRate")
ax1.set_title("Rates over time for asset cdxUSD (0x13aa49bac059d709dd0a18d6bb63290076a702d7)")
ax1.set_ylabel("Rates (in %)")
if log : 
    ax1.set_yscale('log')  # Set y-axis to log scale
ax1.legend()
ax1.grid(True)

# Lower subplot: utilizationRate
ax2.plot(asset_data["timestamp"], asset_data["utilizationRate"] / 1e25, color='green', label="utilizationRate")
ax2.set_xlabel("Timestamp")
ax2.set_ylabel("Utilization Rate (in %)")
if log : 
    ax2.set_yscale('log')  # Set y-axis to log scale
ax2.legend()
ax2.grid(True)

plt.tight_layout()
plt.savefig('datas/rates_over_time.png')
