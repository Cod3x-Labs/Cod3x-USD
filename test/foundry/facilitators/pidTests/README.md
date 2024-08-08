# PID test suit

Directly modify the `testPid()` function by using local helpers:
- `deposit(address user, IERC20 asset, uint256 amount)`
- `borrow(address user, IERC20 asset, uint256 amount)`
- `withdraw(address user, IERC20 asset, uint256 amount)`
- `repay(address user, IERC20 asset, uint256 amount)`

The python script will plot some graphs.

## Requirements

Install [Foundry](https://github.com/foundry-rs/foundry).

Install [Python](https://www.python.org/downloads/).

```sh
forge install
mv .env.example .env
```

## Setup python

```sh
python3 -m venv pyenv
source pyenv/bin/activate
pip install -r test/foundry/facilitators/pidTests/requirements.txt
```

## Execute

```sh
cd test/foundry/facilitators/pidTests
touch datas/output.csv
sudo chmod +x execSimualtion.sh
./execSimualtion.sh
```

## Tune
Stablecoin market:
M_FACTOR = 120e25; // x * y = k, 80 * 120 = 9600
N_FACTOR = 4;

-80e25, // minControllerError // negative amplitude of optimal (more volatile = lower optimal = high minimum)
80e25, // optimalUtilizationRate // guides the tune
1e27, // Kp
13e19, // Ki
0 // Kd

Volatile market:
M_FACTOR = 192e25; // y = k / x, 9600 / 50 = 192
N_FACTOR = 4; // remains constant

-50e25, // minControllerError // negative amplitude of optimal
50e25, // optimalUtilizationRate // guides the tune
1e27, // Kp // remains 1e27
13e19, // Ki // can remain constant tbh, otherwise x * y = k applies also
0 // Kd