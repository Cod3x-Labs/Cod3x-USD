// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

/// Cod3x Vault imports
import "lib/Cod3x-Vault/src/ReaperBaseStrategyv4.sol";
import "lib/Cod3x-Vault/lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";

/// Reliquary imports
import "contracts/interfaces/IReliquary.sol";

/// OpenZeppelin imports
import "@openzeppelin/contracts/interfaces/IERC20.sol";

/// Balancer imports
import {IVault as IBalancerVault} from
    "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVault.sol";

/// Internal imports
import {BalancerV3Router} from "./libraries/BalancerV3Router.sol";

/**
 * @title ScdxUsdVaultStrategy Contract.
 * @author Cod3x - Beirao.
 * @notice This contract is a Cod3x Vault strategy that defines the Staked cdxUSD logic.
 * @dev Keepers need to call `setMinBPTAmountOut()` + `harvest()` every day.
 */
contract ScdxUsdVaultStrategy is ReaperBaseStrategyv4, IERC721Receiver {
    /// @dev ID of the relic used by this strategy.
    uint256 private constant RELIC_ID = 1;
    /// @dev Number of tokens in the Balancer pool.
    uint256 private constant NB_BALANCER_POOL_ASSET = 2;

    /// @dev Reference to the cdxUSD token contract.
    IERC20 public cdxUSD;
    /// @dev Reference to the Reliquary staking contract.
    IReliquary public reliquary;
    /// @dev Reference to the Balancer vault contract.
    IBalancerVault public balancerVault;
    /// @dev Reference to the BalancerV3Router contract.
    BalancerV3Router public balancerV3Router;

    /// @dev Address of the Balancer pool.
    address public balancerPool;
    /// @dev Index of cdxUSD in the pool tokens array.
    uint256 public cdxUsdIndex;
    /// @dev Minimum BPT tokens to receive when joining pool, used for slippage protection.
    uint256 public minBPTAmountOut;

    /// @dev Thrown when input parameters are invalid.
    error ScdxUsdVaultStrategy__INVALID_INPUT();
    /// @dev Thrown when funds are still staked in Reliquary.
    error ScdxUsdVaultStrategy__FUND_STILL_IN_RELIQUARY();
    /// @dev Thrown when token addresses are in wrong order.
    error ScdxUsdVaultStrategy__ADDRESS_WRONG_ORDER();
    /// @dev Thrown when strategy does not own relic ID 1.
    error ScdxUsdVaultStrategy__SHOULD_OWN_RELIC_1();
    /// @dev Thrown when cdxUSD is not in Balancer pool.
    error ScdxUsdVaultStrategy__CDXUSD_NOT_INCLUDED_IN_BALANCER_POOL();
    /// @dev Thrown when minBPTAmountOut is not set.
    error ScdxUsdVaultStrategy__NO_SLIPPAGE_PROTECTION();
    /// @dev Thrown when pool has more than one counter asset.
    error ScdxUsdVaultStrategy__MORE_THAN_1_COUNTER_ASSET();

    /**
     * @dev Initializes the strategy with core parameters and permissions.
     * @param _code3xVault Address of the Cod3x vault contract.
     * @param _balancerVault Address of the Balancer vault contract.
     * @param _balancerV3Router Address of the BalancerV3Router contract.
     * @param _strategists Array of strategist addresses.
     * @param _multisigRoles Array of multisig role addresses.
     * @param _keepers Array of keeper addresses.
     * @param _cdxUSD Address of the cdxUSD token.
     * @param _reliquary Address of the Reliquary staking contract.
     * @param _balancerPool Address of the Balancer pool.
     */
    function initialize(
        address _code3xVault,
        address _balancerVault,
        address _balancerV3Router,
        address[] memory _strategists,
        address[] memory _multisigRoles,
        address[] memory _keepers,
        address _cdxUSD,
        address _reliquary,
        address _balancerPool
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
        minBPTAmountOut = 1;
        cdxUsdIndex = type(uint256).max;
        balancerPool = _balancerPool;
        balancerV3Router = BalancerV3Router(_balancerV3Router);

        IERC20[] memory poolTokens_ = IBalancerVault(_balancerVault).getPoolTokens(_balancerPool);
        if (poolTokens_.length != NB_BALANCER_POOL_ASSET) {
            revert ScdxUsdVaultStrategy__MORE_THAN_1_COUNTER_ASSET();
        }

        IERC20(_cdxUSD).approve(_balancerV3Router, type(uint256).max);

        for (uint256 i = 0; i < NB_BALANCER_POOL_ASSET; i++) {
            if (cdxUSD == poolTokens_[i]) {
                cdxUsdIndex = i;
            }
        }

        if (cdxUsdIndex == type(uint256).max) {
            revert ScdxUsdVaultStrategy__CDXUSD_NOT_INCLUDED_IN_BALANCER_POOL();
        }
    }

    /// ----------- Admin functions -----------

    /**
     * @dev Updates the Reliquary contract address.
     * @param _reliquary New Reliquary contract address.
     */
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
     * @dev Returns total amount of want tokens staked in Reliquary.
     * @return Amount of want tokens in Reliquary.
     */
    function balanceOfPool() public view override returns (uint256) {
        return reliquary.getAmountInRelic(RELIC_ID);
    }

    /**
     * @dev Liquidates all positions by withdrawing from Reliquary.
     * @dev First tries normal withdraw, falls back to emergency withdraw if needed.
     * @dev Admin can pause Reliquary to force emergency withdraw.
     * @return Amount of want tokens withdrawn.
     */
    function _liquidateAllPositions() internal override returns (uint256) {
        try reliquary.withdraw(balanceOfPool(), RELIC_ID, address(this)) {}
        catch {
            reliquary.emergencyWithdraw(RELIC_ID);
        }

        return balanceOfWant();
    }

    /**
     * @dev Deposits want tokens into Reliquary for staking.
     * @param _toReinvest Amount of want tokens to deposit.
     */
    function _deposit(uint256 _toReinvest) internal override {
        if (_toReinvest != 0) {
            reliquary.deposit(_toReinvest, RELIC_ID, address(0));
        }
    }

    /**
     * @dev Withdraws want tokens from Reliquary.
     * @param _amount Amount of want tokens to withdraw.
     */
    function _withdraw(uint256 _amount) internal override {
        if (balanceOfPool() != 0 && _amount != 0) {
            reliquary.withdraw(_amount, RELIC_ID, address(0));
        }
    }

    /**
     * @dev Core harvest logic - claims rewards and joins Balancer pool.
     * @dev Keepers must call setMinBPTAmountOut() before harvest.
     */
    function _harvestCore() internal override {
        if (minBPTAmountOut <= 1) revert ScdxUsdVaultStrategy__NO_SLIPPAGE_PROTECTION();

        reliquary.update(RELIC_ID, address(this));

        uint256 balanceCdxUSD = cdxUSD.balanceOf(address(this));
        if (balanceCdxUSD != 0) {
            uint256[] memory amountsToAdd_ = new uint256[](NB_BALANCER_POOL_ASSET);
            amountsToAdd_[cdxUsdIndex] = balanceCdxUSD;

            balancerV3Router.addLiquidityUnbalanced(balancerPool, amountsToAdd_, minBPTAmountOut);
        }

        minBPTAmountOut = 1;
    }

    /**
     * @dev Sets minimum BPT tokens to receive when joining pool.
     * @param _minBPTAmountOut Minimum BPT tokens to receive.
     */
    function setMinBPTAmountOut(uint256 _minBPTAmountOut) external {
        _atLeastRole(KEEPER);
        minBPTAmountOut = _minBPTAmountOut;
    }

    /**
     * @dev Required for ERC721 token receiver interface.
     * @return bytes4 Function selector.
     */
    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }
}
