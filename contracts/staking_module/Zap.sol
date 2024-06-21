// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "contracts/staking_module/reliquary/interfaces/IReliquary.sol";
import {ReaperVaultV2 as Cod3xVault} from "lib/Cod3x-Vault/src/ReaperVaultV2.sol";
import {ScdxUsdVaultStrategy} from
    "contracts/staking_module/vault_strategy/ScdxUsdVaultStrategy.sol";
import {
    IVault as IBalancerVault,
    JoinKind,
    ExitKind,
    SwapKind
} from "contracts/staking_module/vault_strategy/interfaces/IVault.sol";
import "contracts/staking_module/vault_strategy/libraries/BalancerHelper.sol";
import {IAsset} from "node_modules/@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";

// OZ
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Zap is Pausable, Ownable {
    using SafeERC20 for IERC20;

    uint256 private NB_BALANCER_POOL_ASSET = 3;
    uint8 private RELIQUARY_POOL_ID = 0;

    IBalancerVault public immutable balancerVault;
    Cod3xVault public immutable cod3xVault;
    ScdxUsdVaultStrategy public immutable strategy;
    IReliquary public immutable reliquary;
    IERC20 public immutable poolAdd;
    IERC20 public immutable cdxUsd;
    IERC20 public immutable usdc;
    IERC20 public immutable usdt;

    IAsset[] private poolTokens;
    mapping(address => uint256) private tokenToIndex;
    bytes32 private immutable poolId;

    /// Errors
    error Zap__WRONG_INPUT();
    error Zap__CONTRACT_NOT_COMPATIBLE();
    error Zap__SLIPPAGE_CHECK_FAILED();
    error Zap__RELIC_NOT_OWNED();

    constructor(
        address _balancerVault,
        address _cod3xVault,
        address _strategy,
        address _reliquary,
        address _cdxUsd,
        address _usdc,
        address _usdt,
        address _initialOwner
    ) Ownable(_initialOwner) {
        balancerVault = IBalancerVault(_balancerVault);
        cod3xVault = Cod3xVault(_cod3xVault);
        strategy = ScdxUsdVaultStrategy(_strategy);
        reliquary = IReliquary(_reliquary);
        cdxUsd = IERC20(_cdxUsd);
        usdc = IERC20(_usdc);
        usdt = IERC20(_usdt);

        poolId = ScdxUsdVaultStrategy(_strategy).poolId();

        (IERC20[] memory poolTokens_,,) = IBalancerVault(_balancerVault).getPoolTokens(poolId);

        for (uint256 i = 0; i < poolTokens_.length; i++) {
            poolTokens.push(IAsset(address(poolTokens_[i])));
        }

        (address _poolAdd,) = IBalancerVault(_balancerVault).getPool(poolId);
        poolTokens_ = BalancerHelper._dropBptItem(poolTokens_, _poolAdd);
        poolAdd = IERC20(_poolAdd);

        for (uint256 i = 0; i < poolTokens_.length; i++) {
            tokenToIndex[address(poolTokens_[i])] = i;
        }

        // Compatibility checks
        {
            if (poolTokens_.length != NB_BALANCER_POOL_ASSET) revert Zap__CONTRACT_NOT_COMPATIBLE();
            if (IReliquary(_reliquary).getPoolInfo(RELIQUARY_POOL_ID).poolToken != _poolAdd) {
                revert Zap__CONTRACT_NOT_COMPATIBLE();
            }
            if (ScdxUsdVaultStrategy(_strategy).want() != _poolAdd) {
                revert Zap__CONTRACT_NOT_COMPATIBLE();
            }
            if (ScdxUsdVaultStrategy(_strategy).vault() != _cod3xVault) {
                revert Zap__CONTRACT_NOT_COMPATIBLE();
            }
            if (address(Cod3xVault(_cod3xVault).token()) != _poolAdd) {
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
            if (ScdxUsdVaultStrategy(_strategy).poolId() != poolId) {
                revert Zap__CONTRACT_NOT_COMPATIBLE();
            }
            if (ScdxUsdVaultStrategy(_strategy).cdxUsdIndex() != tokenToIndex[address(cdxUsd)]) {
                revert Zap__CONTRACT_NOT_COMPATIBLE();
            }
        }

        // Approvals
        {
            IERC20(_cdxUsd).approve(_balancerVault, type(uint256).max);
            IERC20(_usdc).approve(_balancerVault, type(uint256).max);
            IERC20(_usdt).approve(_balancerVault, type(uint256).max);
            IERC20(_poolAdd).approve(_cod3xVault, type(uint256).max);
            IERC20(_poolAdd).approve(_reliquary, type(uint256).max);
            IERC20(_cod3xVault).approve(_balancerVault, type(uint256).max);
        }
    }

    /// =============== Admin ===============

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    /// ============ Staked cdxUSD ============

    /**
     * @notice Zap all staking operations into a simple tx:
     *         - join balancer pool
     *         - deposit into cod3x vault
     *         - send scdxUSD to user
     * @dev Users must first approve the amount they wish to send.
     * @param _cdxUsdAmt cdxUSD amount to supply.
     * @param _usdcAmt usdc amount to supply.
     * @param _usdtAmt usdt amount to supply.
     * @param _minScdxUsdOut slippage protection.
     * @param _to address receiving scdxUSD.
     */
    function zapInStakedCdxUSD(
        uint256 _cdxUsdAmt,
        uint256 _usdcAmt,
        uint256 _usdtAmt,
        address _to,
        uint256 _minScdxUsdOut
    ) external whenNotPaused {
        if (
            _cdxUsdAmt == 0 && _usdcAmt == 0 && _usdtAmt == 0 || _minScdxUsdOut == 0
                || _to == address(0)
        ) revert Zap__WRONG_INPUT();

        if (_cdxUsdAmt != 0) cdxUsd.transferFrom(msg.sender, address(this), _cdxUsdAmt);
        if (_usdcAmt != 0) usdc.safeTransferFrom(msg.sender, address(this), _usdcAmt);
        if (_usdtAmt != 0) usdt.safeTransferFrom(msg.sender, address(this), _usdtAmt);

        /// Join pool
        uint256[] memory amountsToAdd_ = new uint256[](NB_BALANCER_POOL_ASSET);
        amountsToAdd_[tokenToIndex[address(cdxUsd)]] = _cdxUsdAmt;
        amountsToAdd_[tokenToIndex[address(usdc)]] = _usdcAmt;
        amountsToAdd_[tokenToIndex[address(usdt)]] = _usdtAmt;

        BalancerHelper._joinPool(
            balancerVault, amountsToAdd_, poolId, poolTokens, 0 /* minBPTAmountOut */
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
        BalancerHelper._exitPool(
            balancerVault,
            poolAdd.balanceOf(address(this)),
            poolId,
            poolTokens,
            _tokenToWithdraw,
            tokenToIndex[_tokenToWithdraw],
            _minAmountOut
        );

        /// Send token
        IERC20(_tokenToWithdraw).transfer(_to, IERC20(_tokenToWithdraw).balanceOf(address(this)));
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
     * @param _usdcAmt usdc amount to supply.
     * @param _usdtAmt usdt amount to supply.
     * @param _to address receiving the relic.
     * @param _minBPTAmountOut slippage protection.
     */
    function zapInRelic(
        uint256 _relicId,
        uint256 _cdxUsdAmt,
        uint256 _usdcAmt,
        uint256 _usdtAmt,
        address _to,
        uint256 _minBPTAmountOut
    ) external whenNotPaused {
        if (
            _cdxUsdAmt == 0 && _usdcAmt == 0 && _usdtAmt == 0 || _to == address(0)
                || _minBPTAmountOut == 0
        ) {
            revert Zap__WRONG_INPUT();
        }

        if (_cdxUsdAmt != 0) cdxUsd.safeTransferFrom(msg.sender, address(this), _cdxUsdAmt);
        if (_usdcAmt != 0) usdc.safeTransferFrom(msg.sender, address(this), _usdcAmt);
        if (_usdtAmt != 0) usdt.safeTransferFrom(msg.sender, address(this), _usdtAmt);

        /// Join pool
        uint256[] memory amountsToAdd_ = new uint256[](NB_BALANCER_POOL_ASSET);
        amountsToAdd_[tokenToIndex[address(cdxUsd)]] = _cdxUsdAmt;
        amountsToAdd_[tokenToIndex[address(usdc)]] = _usdcAmt;
        amountsToAdd_[tokenToIndex[address(usdt)]] = _usdtAmt;

        BalancerHelper._joinPool(balancerVault, amountsToAdd_, poolId, poolTokens, _minBPTAmountOut);

        /// Reliquary deposit
        if (_relicId != 0) {
            if (!reliquary.isApprovedOrOwner(msg.sender, _relicId) || _to != msg.sender) {
                revert Zap__RELIC_NOT_OWNED();
            }
            reliquary.deposit(poolAdd.balanceOf(address(this)), _relicId, address(0));
        } else {
            reliquary.createRelicAndDeposit(
                _to, RELIQUARY_POOL_ID, poolAdd.balanceOf(address(this))
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
     * @param _amountBtpToWithdraw amount of token to withdraw.
     * @param _tokenToWithdraw address of the token to be withdrawn.
     * @param _minAmountOut slippage protection.
     * @param _to address receiving tokens. (harvest rewards and principal)
     */
    function zapOutRelic(
        uint256 _relicId,
        uint256 _amountBtpToWithdraw,
        address _tokenToWithdraw,
        uint256 _minAmountOut,
        address _to
    ) external whenNotPaused {
        if (_relicId == 0 || _amountBtpToWithdraw == 0 || _minAmountOut == 0 || _to == address(0)) {
            revert Zap__WRONG_INPUT();
        }

        if (!reliquary.isApprovedOrOwner(msg.sender, _relicId)) {
            revert Zap__RELIC_NOT_OWNED();
        }

        /// Reliquary withdraw
        reliquary.withdraw(_amountBtpToWithdraw, _relicId, address(_to));

        /// withdraw pool
        BalancerHelper._exitPool(
            balancerVault,
            poolAdd.balanceOf(address(this)),
            poolId,
            poolTokens,
            _tokenToWithdraw,
            tokenToIndex[_tokenToWithdraw],
            _minAmountOut
        );

        /// Send Relic
        IERC20(_tokenToWithdraw).transfer(_to, IERC20(_tokenToWithdraw).balanceOf(address(this)));
    }
}
