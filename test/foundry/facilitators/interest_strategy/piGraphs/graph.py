import pandas as pd
import matplotlib.pyplot as plt
import os
import numpy as np

log = False

# Load the CSV file
asset = "0x13aa49bac059d709dd0a18d6bb63290076a702d7"
if "pidTests" in os.getcwd():
    dir = os.getcwd() + "/data"
else:
    dir = os.getcwd() + "/test/foundry/facilitators/interest_strategy/piGraphs"
idx = 0
print(dir)

liquidities = []
debts = []
timestamp = []
names = []
linestyles = ['-.', '--', ':']

for root, dirs, filenames in os.walk(dir):
    for filename in filenames:
        
        if ".csv" in filename:
            names.append(filename.split(".")[0])
            print("Filename: {}".format(filename))
            # Load the CSV file
            print(os.path.join(root, filename))
            data = pd.read_csv(os.path.join(root, filename))

            # Filter the data for the specified asset
            print(data)
            asset_data = data[data["asset"] == asset].copy()

            # Convert the timestamp to datetime and the rates to float
            asset_data["timestamp"] = asset_data["timestamp"] / 86400 
            asset_data["currentVariableBorrowRate"] = asset_data["currentVariableBorrowRate"].astype(float)
            asset_data["optimalStablePoolReserveUtilization"] = asset_data["optimalStablePoolReserveUtilization"].astype(float)
            asset_data["utilizationRate"] = asset_data["utilizationRate"].astype(float)

            # Create a figure with two subplots
            fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8), sharex=True)

            # Upper subplot: currentVariableBorrowRate and currentLiquidityRate
            ax1.plot(asset_data["timestamp"], asset_data["currentVariableBorrowRate"] / 1e25, label="currentVariableBorrowRate")
            ax1.set_title("Rates over time for asset {}".format(asset))
            ax1.set_ylabel("Rates (in %)")
            if log : 
                ax1.set_yscale('log')  # Set y-axis to log scale
            ax1.legend()
            ax1.grid(True)

            # Lower subplot: utilizationRate
            ax2.plot(asset_data["timestamp"], asset_data["utilizationRate"] / 1e25, color='green', label="utilizationRate")
            ax2.plot(asset_data["timestamp"], asset_data["optimalStablePoolReserveUtilization"] / 1e25, color='red', label="optimalStablePoolReserveUtilization")
            ax2.set_xlabel("Timestamp")
            ax2.set_ylabel("Utilization Rate (in %)")
            if log : 
                ax2.set_yscale('log')  # Set y-axis to log scale
            ax2.grid(which='minor', color='gray', linestyle=':', linewidth=0.3)
            # ax2.set_xticks(np.arange(0, 16, 0.2), minor=True)
            # ax2.set_yticks(np.arange(20, 40, 1), minor=True)
            ax2.legend()
            ax2.grid(True)

            plt.tight_layout()
            plt.savefig(os.getcwd() + "/test/foundry/facilitators/interest_strategy/piGraphs/rates_over_time_{}.png".format(filename.split(".")[0]))