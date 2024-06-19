// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "lib/Cod3x-Vault/src/ReaperBaseStrategyv4.sol";
import "contracts/staking_module/reliquary/interfaces/IReliquary.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IVault as IBalancerVault, JoinKind, ExitKind, SwapKind} from "./interfaces/IVault.sol"; // balancer Vault
import {IAsset} from "node_modules/@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import "./interfaces/IBaseBalancerPool.sol";
import "./libraries/BalancerHelper.sol";

/**
 * @title ScdxUsdVaultStrategy Contract
 * @author Cod3X Labs - Beirao
 * @notice This contract is Cod3x Vault strategy that define the Staked cdxUSD logic.
 * @dev Keepers needs to call `setMinBPTAmountOut()` + `harvest()` every days.
 */
contract ScdxUsdVaultStrategy is ReaperBaseStrategyv4 {
    uint256 private constant RELIC_ID = 1;

    IERC20 public cdxUSD;
    IReliquary public reliquary;
    IBalancerVault public balancerVault;

    IAsset[] public poolTokens;
    bytes32 public poolId;
    uint256 public cdxUsdIndex;
    uint256 public minBPTAmountOut;

    /// Errors
    error ScdxUsdVaultStrategy__INVALID_INPUT();
    error ScdxUsdVaultStrategy__FUND_STILL_IN_RELIQUARY();
    error ScdxUsdVaultStrategy__ADDRESS_WRONG_ORDER();
    error ScdxUsdVaultStrategy__SHOULD_OWN_RELIC_1();
    error ScdxUsdVaultStrategy__CDXUSD_NOT_INCLUDED_IN_BALANCER_POOL();
    error ScdxUsdVaultStrategy__NO_SLIPPAGE_PROTECTION();

    /**
     * @dev Initializes the strategy. Sets parameters, saves routes, and gives allowances.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _code3xVault,
        address _balancerVault,
        address[] memory _strategists,
        address[] memory _multisigRoles,
        address[] memory _keepers,
        address _cdxUSD,
        address _reliquary,
        address _balancerPool,
        bytes32 _poolId
    ) public initializer {
        if (
            _code3xVault == address(0) || _reliquary == address(0) || _strategists.length == 0
                || _multisigRoles.length != 3
        ) revert ScdxUsdVaultStrategy__INVALID_INPUT();

        if (!IReliquary(_reliquary).isApprovedOrOwner(address(this), RELIC_ID)) {
            revert ScdxUsdVaultStrategy__SHOULD_OWN_RELIC_1();
        }

        address poolToken_ = IReliquary(_reliquary).getPoolInfo(
            IReliquary(_reliquary).getPositionForId(RELIC_ID).poolId
        ).poolToken;

        __ReaperBaseStrategy_init(
            _code3xVault,
            address(0),
            poolToken_, // get the Relic#1 pool token.
            _strategists,
            _multisigRoles,
            _keepers
        );

        cdxUSD = IERC20(_cdxUSD);
        balancerVault = IBalancerVault(_balancerVault);
        IERC20(poolToken_).approve(_reliquary, type(uint256).max);

        reliquary = IReliquary(_reliquary);
        poolId = _poolId;
        minBPTAmountOut = 1;
        cdxUsdIndex = type(uint256).max;

        (IERC20[] memory poolTokens_,,) = IBalancerVault(_balancerVault).getPoolTokens(_poolId);

        for (uint256 i = 0; i < poolTokens_.length; i++) {
            poolTokens.push(IAsset(address(poolTokens_[i])));
        }

        IERC20(_cdxUSD).approve(_balancerVault, type(uint256).max);

        (address _poolAdd,) = IBalancerVault(_balancerVault).getPool(poolId);
        poolTokens_ = BalancerHelper._dropBptItem(poolTokens_, _poolAdd); // TODO octocheck this
        for (uint256 i = 0; i < poolTokens_.length; i++) {
            if (cdxUSD == poolTokens_[i]) {
                cdxUsdIndex = i;
            }
        }

        if (cdxUsdIndex == type(uint256).max) {
            revert ScdxUsdVaultStrategy__CDXUSD_NOT_INCLUDED_IN_BALANCER_POOL();
        }
    }

    /// ----------- Admin functions -----------

    function setReliquary(address _reliquary) public {
        _atLeastRole(ADMIN);
        if (_reliquary == address(0)) {
            revert ScdxUsdVaultStrategy__INVALID_INPUT();
        }

        if (balanceOfPool() != 0) {
            revert ScdxUsdVaultStrategy__FUND_STILL_IN_RELIQUARY();
        }

        reliquary = IReliquary(_reliquary);

        address poolToken_ = IReliquary(_reliquary).getPoolInfo(
            IReliquary(_reliquary).getPositionForId(RELIC_ID).poolId
        ).poolToken;

        IERC20(poolToken_).approve(_reliquary, type(uint256).max);
    }

    /// -------------- Overrides --------------

    /**
     * @dev Function to calculate the total {want} in external contracts only.
     */
    function balanceOfPool() public view override returns (uint256) {
        return reliquary.getAmountInRelic(RELIC_ID);
    }

    /**
     * @dev First try to liquidate with `withdraw()`, if it fails try to liquidate with `emergencyWithdraw()`.
     * If `withdraw()` should not be called, admin can still pause the reliquary contract, this will
     * make `withdraw()` reverts and automatically call `emergencyWithdraw()`.
     */
    function _liquidateAllPositions() internal override returns (uint256) {
        try reliquary.withdraw(balanceOfPool(), RELIC_ID, address(this)) {}
        catch {
            reliquary.emergencyWithdraw(RELIC_ID);
        }

        return balanceOfWant();
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever the vault has allocated more free want to this strategy that can be
     * deposited in external contracts to generate yield.
     */
    function _deposit(uint256 _toReinvest) internal override {
        if (_toReinvest != 0) {
            reliquary.deposit(_toReinvest, RELIC_ID, address(0));
        }
    }

    /**
     * @dev Withdraws funds from external contracts and brings them back to the strategy.
     */
    function _withdraw(uint256 _amount) internal override {
        if (balanceOfPool() != 0 && _amount != 0) {
            reliquary.withdraw(_amount, RELIC_ID, address(0));
        }
    }

    /**
     * @notice Before calling `harvest()` KEEPERs must call `setMinBPTAmountOut()`.
     * @dev Steps:
     *          - harvest cdxUSD from reliquary.
     *          - join balancer pool and get LP tokens.
     */
    function _harvestCore() internal override {
        if (minBPTAmountOut <= 1) revert ScdxUsdVaultStrategy__NO_SLIPPAGE_PROTECTION();

        reliquary.update(RELIC_ID, address(this));

        uint256 balanceCdxUSD = cdxUSD.balanceOf(address(this));
        if (balanceCdxUSD != 0) {
            uint256[] memory amountsToAdd_ = new uint256[](poolTokens.length - 1);
            amountsToAdd_[cdxUsdIndex] = balanceCdxUSD;

            BalancerHelper._joinPool(
                balancerVault, amountsToAdd_, poolId, poolTokens, minBPTAmountOut
            );
        }

        minBPTAmountOut = 1;
    }

    /**
     * @notice define minBPTAmountOut. Must be called before harvesting.
     * @param _minBPTAmountOut Mininum PoolToken out for the next harvest.
     */
    function setMinBPTAmountOut(uint256 _minBPTAmountOut) external {
        _atLeastRole(KEEPER);
        minBPTAmountOut = _minBPTAmountOut;
    }
}
