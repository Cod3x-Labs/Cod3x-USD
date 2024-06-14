// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "lib/Cod3x-Vault/src/ReaperBaseStrategyv4.sol";
import "contracts/staking_module/reliquary/interfaces/IReliquary.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IVault as IBalancerVault, JoinKind, ExitKind, SwapKind} from "./interfaces/IVault.sol"; // balancer Vault
import {IAsset} from "node_modules/@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";

/// Errors
error ScdxUsdVaultStrategy__INVALID_INPUT();
error ScdxUsdVaultStrategy__FUND_STILL_IN_RELIQUARY();
error ScdxUsdVaultStrategy__ADDRESS_WRONG_ORDER();
error ScdxUsdVaultStrategy__SHOULD_OWN_RELIC_1();
error ScdxUsdVaultStrategy__CDXUSD_NOT_INCLUDED_IN_BALANCER_POOL();
error ScdxUsdVaultStrategy__NO_SLIPPAGE_PROTECTION();

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

    IAsset[] public poolTokens;
    bytes32 public poolId;
    uint256 public cdxUsdIndex = type(uint256).max;
    uint256 public minBPTAmountOut = 1;

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

        if (!IReliquary(_reliquary).isApprovedOrOwner(address(this), 1)) {
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

        IERC20(poolToken_).approve(_reliquary, type(uint256).max);

        reliquary = IReliquary(_reliquary);
        poolId = _poolId;

        (IERC20[] memory poolTokens_,,) = IBalancerVault(_balancerVault).getPoolTokens(_poolId);

        for (uint256 i = 0; i < poolTokens_.length; i++) {
            poolTokens.push(IAsset(address(poolTokens_[i])));
        }

        IERC20(_cdxUSD).approve(_balancerVault, type(uint256).max);

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
    function _liquidateAllPositions() internal override returns (uint256 amountFreed) {
        uint256 balanceBefore_ = IERC20(want).balanceOf(address(this));

        try reliquary.withdraw(amountFreed, RELIC_ID, address(this)) {}
        catch {
            reliquary.emergencyWithdraw(RELIC_ID);
        }

        amountFreed = IERC20(want).balanceOf(address(this)) - balanceBefore_;
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever the vault has allocated more free want to this strategy that can be
     * deposited in external contracts to generate yield.
     */
    function _deposit(uint256 _toReinvest) internal override {
        reliquary.deposit(RELIC_ID, _toReinvest, address(0));
    }

    /**
     * @dev Withdraws funds from external contracts and brings them back to the strategy.
     */
    function _withdraw(uint256 _amount) internal override {
        reliquary.withdraw(_amount, RELIC_ID, address(0));
    }

    /**
     * @notice Before calling `harvest()` KEEPERs must call `setMinBPTAmountOut()`.
     * @dev Steps:
     *          - harvest cdxUSD from reliquary.
     *          - join balancer pool and get LP tokens.
     */
    function _harvestCore() internal override {
        if (minBPTAmountOut == 1) revert ScdxUsdVaultStrategy__NO_SLIPPAGE_PROTECTION();
        reliquary.update(RELIC_ID, address(this));
        _joinPool(cdxUSD.balanceOf(address(this)));
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

    /// --------------- Helpers ---------------

    function _joinPool(uint256 _amount) internal {
        uint256 len_ = poolTokens.length;

        uint256[] memory amountsToAdd = new uint256[](len_);
        amountsToAdd[cdxUsdIndex] = _amount;

        uint256[] memory maxAmounts = new uint256[](len_);
        for (uint256 i = 0; i < len_; i++) {
            maxAmounts[i] = type(uint256).max;
        }

        IBalancerVault.JoinPoolRequest memory request;
        request.assets = poolTokens;
        request.maxAmountsIn = maxAmounts;
        request.fromInternalBalance = false;
        request.userData =
            abi.encode(JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amountsToAdd, minBPTAmountOut);

        IBalancerVault(vault).joinPool(poolId, address(this), address(this), request);
    }
}
