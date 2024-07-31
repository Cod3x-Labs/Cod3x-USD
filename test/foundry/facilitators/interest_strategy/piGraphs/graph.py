import pandas as pd
import matplotlib.pyplot as plt
import os

log = False

# Load the CSV file
asset = "0x13aa49bac059d709dd0a18d6bb63290076a702d7"
path_to_open = os.getcwd() + "/test/foundry/facilitators/interest_strategy/piGraphs/outputGreaterThanZero.csv"


data = pd.read_csv(path_to_open)

# Filter the data for the specified asset
print(data)
asset_data = data[data["asset"] == asset].copy()

# Convert the timestamp to datetime and the rates to float
asset_data["timestamp"] = asset_data["timestamp"] / 86400 
asset_data["currentVariableBorrowRate"] = asset_data["currentVariableBorrowRate"].astype(float)
asset_data["currentLiquidityRate"] = asset_data["currentLiquidityRate"].astype(float)
asset_data["utilizationRate"] = asset_data["utilizationRate"].astype(float)

# Create a figure with two subplots
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8), sharex=True)

# Upper subplot: currentVariableBorrowRate and currentLiquidityRate
ax1.plot(asset_data["timestamp"], asset_data["currentVariableBorrowRate"] / 1e25, label="currentVariableBorrowRate")
ax1.plot(asset_data["timestamp"], asset_data["currentLiquidityRate"] / 1e25, color='red', label="currentLiquidityRate")
ax1.set_title("Rates over time for asset {}".format(asset))
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
plt.savefig(os.getcwd() + "/test/foundry/facilitators/interest_strategy/piGraphs/rates_over_time.png")