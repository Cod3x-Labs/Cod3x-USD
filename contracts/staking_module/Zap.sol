// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

/// Reliquary imports
import "contracts/interfaces/IReliquary.sol";

/// Cod3x imports
import {ReaperVaultV2 as Cod3xVault} from "lib/Cod3x-Vault/src/ReaperVaultV2.sol";
import {ScdxUsdVaultStrategy} from
    "contracts/staking_module/vault_strategy/ScdxUsdVaultStrategy.sol";

// Balancer imports
import {IVault as IBalancerVault} from
    "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVault.sol";
import {BalancerV3Router} from
    "contracts/staking_module/vault_strategy/libraries/BalancerV3Router.sol";

/// OZ imports
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// balancer V3 imports
import {BalancerV3Router} from
    "contracts/staking_module/vault_strategy/libraries/BalancerV3Router.sol";

/**
 * @title Zap
 * @author Cod3x - Beirao
 * @notice Zap all possible scdxUSD operations.
 */
contract Zap is Pausable, Ownable {
    using SafeERC20 for IERC20;
    /// @dev Number of tokens in the Balancer pool. Must be 2 for this implementation.

    uint256 private NB_BALANCER_POOL_ASSET = 2;
    /// @dev ID of the Reliquary pool where BPT tokens are staked.
    uint8 private RELIQUARY_POOL_ID = 0;

    /// @dev Reference to the Balancer vault contract for pool interactions.
    IBalancerVault public immutable balancerVault;
    /// @dev Reference to the Cod3x vault contract where scdxUSD is deposited.
    Cod3xVault public immutable cod3xVault;
    /// @dev Reference to the vault strategy contract that manages scdxUSD deposits.
    ScdxUsdVaultStrategy public immutable strategy;
    /// @dev Reference to the Reliquary staking contract.
    IReliquary public immutable reliquary;
    /// @dev Reference to the cdxUSD token contract.
    IERC20 public immutable cdxUsd;
    /// @dev Reference to the counter asset token (USDC/USDT).
    IERC20 public immutable counterAsset;
    /// @dev Address with guardian privileges for emergency functions.
    address public guardian;
    /// @dev Reference to the BalancerV3Router contract.
    BalancerV3Router public immutable balancerV3Router;

    /// @dev Maps token addresses to their index in the pool tokens array.
    mapping(address => uint256) private tokenToIndex;
    /// @dev Address of the Balancer pool.
    address private immutable balancerPool;

    /// @dev Thrown when input parameters are invalid.
    error Zap__WRONG_INPUT();
    /// @dev Thrown when contract configuration is incompatible.
    error Zap__CONTRACT_NOT_COMPATIBLE();
    /// @dev Thrown when slippage protection check fails.
    error Zap__SLIPPAGE_CHECK_FAILED();
    /// @dev Thrown when caller does not own the specified relic.
    error Zap__RELIC_NOT_OWNED();
    /// @dev Thrown when caller is not the guardian.
    error Zap__ONLY_GUARDIAN();

    /// @dev Restricts function access to the guardian address.
    modifier onlyGuardian() {
        if (msg.sender != guardian) {
            revert Zap__ONLY_GUARDIAN();
        }
        _;
    }

    /**
     * @dev Initializes the contract with core dependencies and configuration.
     * @param _balancerVault Address of the Balancer vault contract.
     * @param _cod3xVault Address of the Cod3x vault contract.
     * @param _balancerV3Router Address of the BalancerV3Router contract.
     * @param _strategy Address of the vault strategy contract.
     * @param _reliquary Address of the Reliquary staking contract.
     * @param _cdxUsd Address of the cdxUSD token.
     * @param _counterAsset Address of the counter asset token.
     * @param _owner Address that will own the contract.
     * @param _guardian Address that will have guardian privileges.
     */
    constructor(
        address _balancerVault,
        address _cod3xVault,
        address _balancerV3Router,
        address _strategy,
        address _reliquary,
        address _cdxUsd,
        address _counterAsset,
        address _owner,
        address _guardian
    ) Ownable(_owner) {
        balancerVault = IBalancerVault(_balancerVault);
        cod3xVault = Cod3xVault(_cod3xVault);
        strategy = ScdxUsdVaultStrategy(_strategy);
        reliquary = IReliquary(_reliquary);
        cdxUsd = IERC20(_cdxUsd);
        counterAsset = IERC20(_counterAsset);
        guardian = _guardian;

        balancerPool = ScdxUsdVaultStrategy(_strategy).balancerPool();
        balancerV3Router = BalancerV3Router(_balancerV3Router);

        IERC20[] memory poolTokens_ = IBalancerVault(_balancerVault).getPoolTokens(balancerPool);

        for (uint256 i = 0; i < poolTokens_.length; i++) {
            tokenToIndex[address(poolTokens_[i])] = i;
        }

        // Compatibility checks
        {
            if (poolTokens_.length != NB_BALANCER_POOL_ASSET) revert Zap__CONTRACT_NOT_COMPATIBLE();
            if (IReliquary(_reliquary).getPoolInfo(RELIQUARY_POOL_ID).poolToken != balancerPool) {
                revert Zap__CONTRACT_NOT_COMPATIBLE();
            }
            if (ScdxUsdVaultStrategy(_strategy).want() != balancerPool) {
                revert Zap__CONTRACT_NOT_COMPATIBLE();
            }
            if (ScdxUsdVaultStrategy(_strategy).vault() != _cod3xVault) {
                revert Zap__CONTRACT_NOT_COMPATIBLE();
            }
            if (address(Cod3xVault(_cod3xVault).token()) != balancerPool) {
                revert Zap__CONTRACT_NOT_COMPATIBLE();
            }
            if (address(ScdxUsdVaultStrategy(_strategy).cdxUSD()) != _cdxUsd) {
                revert Zap__CONTRACT_NOT_COMPATIBLE();
            }
            if (address(ScdxUsdVaultStrategy(_strategy).reliquary()) != _reliquary) {
                revert Zap__CONTRACT_NOT_COMPATIBLE();
            }
            if (address(ScdxUsdVaultStrategy(_strategy).balancerVault()) != _balancerVault) {
                revert Zap__CONTRACT_NOT_COMPATIBLE();
            }
            if (ScdxUsdVaultStrategy(_strategy).balancerPool() != balancerPool) {
                revert Zap__CONTRACT_NOT_COMPATIBLE();
            }
            if (ScdxUsdVaultStrategy(_strategy).cdxUsdIndex() != tokenToIndex[address(cdxUsd)]) {
                revert Zap__CONTRACT_NOT_COMPATIBLE();
            }
        }

        // Approvals
        {
            IERC20(_cdxUsd).approve(_balancerVault, type(uint256).max);
            IERC20(_counterAsset).approve(_balancerVault, type(uint256).max);
            IERC20(_cod3xVault).approve(_balancerVault, type(uint256).max);

            IERC20(_cdxUsd).approve(_balancerV3Router, type(uint256).max);
            IERC20(_counterAsset).approve(_balancerV3Router, type(uint256).max);

            IERC20(balancerPool).approve(_cod3xVault, type(uint256).max);
            IERC20(balancerPool).approve(_reliquary, type(uint256).max);
            IERC20(balancerPool).approve(_balancerV3Router, type(uint256).max);
        }
    }

    /// =============== Admin ===============

    /**
     * @notice Pause the Zap contract.
     * @dev restricted to guardian.
     */
    function pause() public onlyGuardian {
        _pause();
    }

    /**
     * @notice Unpause the Zap contract.
     * @dev restricted to owner.
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @notice set guardian address.
     * @param _guardian guardian address.
     */
    function setGuardian(address _guardian) external onlyOwner {
        if (_guardian == address(0)) revert Zap__WRONG_INPUT();
        guardian = _guardian;
    }

    /// ============ Staked cdxUSD ============

    /**
     * @notice Zap all staking operations into a simple tx:
     *         - join balancer pool
     *         - deposit into cod3x vault
     *         - send scdxUSD to user
     * @dev Users must first approve the amount they wish to send.
     * @param _cdxUsdAmt cdxUSD amount to supply.
     * @param _caAmt counter asset amount to supply.
     * @param _minScdxUsdOut slippage protection.
     * @param _to address receiving scdxUSD.
     */
    function zapInStakedCdxUSD(
        uint256 _cdxUsdAmt,
        uint256 _caAmt,
        address _to,
        uint256 _minScdxUsdOut
    ) external whenNotPaused {
        if (_cdxUsdAmt == 0 && _caAmt == 0 || _minScdxUsdOut == 0 || _to == address(0)) {
            revert Zap__WRONG_INPUT();
        }

        if (_cdxUsdAmt != 0) cdxUsd.transferFrom(msg.sender, address(this), _cdxUsdAmt);
        if (_caAmt != 0) counterAsset.safeTransferFrom(msg.sender, address(this), _caAmt);

        /// Join pool
        uint256[] memory amountsToAdd_ = new uint256[](NB_BALANCER_POOL_ASSET);
        amountsToAdd_[tokenToIndex[address(cdxUsd)]] = _cdxUsdAmt;
        amountsToAdd_[tokenToIndex[address(counterAsset)]] = _caAmt;

        balancerV3Router.addLiquidityUnbalanced(
            balancerPool, amountsToAdd_, 0 /* minBPTAmountOut */
        );

        /// Cod3x Vault deposit
        cod3xVault.depositAll();

        /// Send cdxUSD
        uint256 scdxUsdBalanceOut = cod3xVault.balanceOf(address(this));
        if (scdxUsdBalanceOut < _minScdxUsdOut) revert Zap__SLIPPAGE_CHECK_FAILED();
        cod3xVault.transfer(_to, scdxUsdBalanceOut); // SafeERC20 not needed
    }

    /**
     * @notice Zap all unstaking operations into a simple tx:
     *         - withdraw from cod3x vault
     *         - exit balancer pool
     *         - send token(s) to user
     * @dev Users must first approve the amount they wish to send.
     * @param _scdxUsdAmount scdxUSD amount to withdraw.
     * @param _tokenToWithdraw address of the token to be withdrawn.
     * @param _minAmountOut slippage protection.
     * @param _to address receiving tokens.
     */
    function zapOutStakedCdxUSD(
        uint256 _scdxUsdAmount,
        address _tokenToWithdraw,
        uint256 _minAmountOut,
        address _to
    ) external whenNotPaused {
        if (_scdxUsdAmount == 0 || _minAmountOut == 0 || _to == address(0)) {
            revert Zap__WRONG_INPUT();
        }

        cod3xVault.transferFrom(msg.sender, address(this), _scdxUsdAmount);

        /// Cod3x Vault withdraw
        cod3xVault.withdraw(_scdxUsdAmount);

        /// withdraw pool
        balancerV3Router.removeLiquiditySingleTokenExactIn(
            balancerPool,
            tokenToIndex[_tokenToWithdraw],
            IERC20(balancerPool).balanceOf(address(this)),
            _minAmountOut
        );

        /// Send token
        IERC20(_tokenToWithdraw).safeTransfer(
            _to, IERC20(_tokenToWithdraw).balanceOf(address(this))
        );
    }

    /// ================ Relic ================

    /**
     * @notice Zap all staking operations into a simple tx:
     *         - join balancer pool
     *         - deposit into reliquary
     * @dev Users must first approve the amount they wish to send. `reliquary.approve()`
     * @dev If user wishes to deposit into an already owned relic,
     *      he must first approve this contract.
     * @param _relicId Id of the relic to deposit, 0 will create a new relic.
     * @param _cdxUsdAmt cdxUSD amount to supply.
     * @param _caAmt counter asset amount to supply.
     * @param _to address receiving the relic.
     * @param _minBPTAmountOut slippage protection.
     */
    function zapInRelic(
        uint256 _relicId,
        uint256 _cdxUsdAmt,
        uint256 _caAmt,
        address _to,
        uint256 _minBPTAmountOut
    ) external whenNotPaused {
        if (_cdxUsdAmt == 0 && _caAmt == 0 || _to == address(0) || _minBPTAmountOut == 0) {
            revert Zap__WRONG_INPUT();
        }

        if (_cdxUsdAmt != 0) cdxUsd.safeTransferFrom(msg.sender, address(this), _cdxUsdAmt);
        if (_caAmt != 0) counterAsset.safeTransferFrom(msg.sender, address(this), _caAmt);

        /// Join pool
        uint256[] memory amountsToAdd_ = new uint256[](NB_BALANCER_POOL_ASSET);
        amountsToAdd_[tokenToIndex[address(cdxUsd)]] = _cdxUsdAmt;
        amountsToAdd_[tokenToIndex[address(counterAsset)]] = _caAmt;

        balancerV3Router.addLiquidityUnbalanced(balancerPool, amountsToAdd_, _minBPTAmountOut);

        /// Reliquary deposit
        if (_relicId != 0) {
            if (!reliquary.isApprovedOrOwner(msg.sender, _relicId) || _to != msg.sender) {
                revert Zap__RELIC_NOT_OWNED();
            }
            reliquary.deposit(IERC20(balancerPool).balanceOf(address(this)), _relicId, address(0));
        } else {
            reliquary.createRelicAndDeposit(
                _to, RELIQUARY_POOL_ID, IERC20(balancerPool).balanceOf(address(this))
            );
        }
    }

    /**
     * @notice Zap all unstaking operations into a simple tx:
     *         - withdraw from relic
     *         - exit balancer pool
     *         - send token(s) to user
     * @dev Users must first approve the amount they wish to send.
     * @param _relicId Id of the relic to withdraw from.
     * @param _amountBptToWithdraw amount of token to withdraw.
     * @param _tokenToWithdraw address of the token to be withdrawn.
     * @param _minAmountOut slippage protection.
     * @param _harvestTo address receiving tokens. (harvest rewards and principal)
     */
    function zapOutRelic(
        uint256 _relicId,
        uint256 _amountBptToWithdraw,
        address _tokenToWithdraw,
        uint256 _minAmountOut,
        address _harvestTo
    ) external whenNotPaused {
        if (
            _relicId == 0 || _amountBptToWithdraw == 0 || _minAmountOut == 0
                || _harvestTo == address(0)
        ) {
            revert Zap__WRONG_INPUT();
        }

        if (!reliquary.isApprovedOrOwner(msg.sender, _relicId)) {
            revert Zap__RELIC_NOT_OWNED();
        }

        /// Reliquary withdraw
        reliquary.withdraw(_amountBptToWithdraw, _relicId, address(_harvestTo));

        /// withdraw pool
        balancerV3Router.removeLiquiditySingleTokenExactIn(
            balancerPool,
            tokenToIndex[_tokenToWithdraw],
            IERC20(balancerPool).balanceOf(address(this)),
            _minAmountOut
        );

        /// Send token
        IERC20(_tokenToWithdraw).safeTransfer(
            _harvestTo, IERC20(_tokenToWithdraw).balanceOf(address(this))
        );
    }
}
