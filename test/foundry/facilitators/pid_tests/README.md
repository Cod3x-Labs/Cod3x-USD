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
pip install -r test/foundry/facilitators/pid_tests/requirements.txt
```

## Execute

```sh
cd test/foundry/facilitators/pid_tests
touch datas/output.csv
sudo chmod +x execSimulation.sh
./execSimualtion.sh
```

## Tune
TODO