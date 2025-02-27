// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.23;

import {IERC20Detailed} from "lib/Cod3x-Lend/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {IAToken} from "lib/Cod3x-Lend/contracts/interfaces/IAToken.sol";
import {ILendingPoolAddressesProvider} from "lib/Cod3x-Lend/contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {ILendingPool} from "lib/Cod3x-Lend/contracts/interfaces/ILendingPool.sol";
import {IVariableDebtToken} from "lib/Cod3x-Lend/contracts/interfaces/IVariableDebtToken.sol";
import {ReserveConfiguration} from "lib/Cod3x-Lend/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from "lib/Cod3x-Lend/contracts/protocol/libraries/configuration/UserConfiguration.sol";
import {DataTypes} from "lib/Cod3x-Lend/contracts/protocol/libraries/types/DataTypes.sol";

/**
 * @title ProtocolDataProvider
 * @author Cod3x
 */
contract ProtocolDataProvider {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    address constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct TokenData {
        string symbol;
        address tokenAddress;
    }

    ILendingPoolAddressesProvider public immutable ADDRESSES_PROVIDER;

    constructor(ILendingPoolAddressesProvider addressesProvider) {
        ADDRESSES_PROVIDER = addressesProvider;
    }

    function getAllReservesTokens() external view returns (TokenData[] memory) {
        ILendingPool pool = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());
        address[] memory reserves = new address[](pool.getReservesCount());
        (reserves,) = pool.getReservesList();
        TokenData[] memory reservesTokens = new TokenData[](reserves.length);
        for (uint256 i = 0; i < reserves.length; i++) {
            if (reserves[i] == MKR) {
                reservesTokens[i] = TokenData({symbol: "MKR", tokenAddress: reserves[i]});
                continue;
            }
            if (reserves[i] == ETH) {
                reservesTokens[i] = TokenData({symbol: "ETH", tokenAddress: reserves[i]});
                continue;
            }
            reservesTokens[i] =
                TokenData({symbol: IERC20Detailed(reserves[i]).symbol(), tokenAddress: reserves[i]});
        }
        return reservesTokens;
    }

    function getAllATokens() external view returns (TokenData[] memory) {
        ILendingPool pool = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());
        address[] memory reserves = new address[](pool.getReservesCount());
        bool[] memory reservesTypes = new bool[](pool.getReservesCount());
        (reserves, reservesTypes) = pool.getReservesList();
        TokenData[] memory aTokens = new TokenData[](reserves.length);
        for (uint256 i = 0; i < reserves.length; i++) {
            DataTypes.ReserveData memory reserveData =
                pool.getReserveData(reserves[i], reservesTypes[i]);
            aTokens[i] = TokenData({
                symbol: IERC20Detailed(reserveData.aTokenAddress).symbol(),
                tokenAddress: reserveData.aTokenAddress
            });
        }
        return aTokens;
    }

    function getReserveConfigurationData(address asset, bool reserveType)
        external
        view
        returns (
            uint256 decimals,
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 reserveFactor,
            bool usageAsCollateralEnabled,
            bool borrowingEnabled,
            bool isActive,
            bool isFrozen
        )
    {
        DataTypes.ReserveConfigurationMap memory configuration =
            ILendingPool(ADDRESSES_PROVIDER.getLendingPool()).getConfiguration(asset, reserveType);

        (ltv, liquidationThreshold, liquidationBonus, decimals, reserveFactor,,) =
            configuration.getParamsMemory();

        (isActive, isFrozen, borrowingEnabled,) = configuration.getFlagsMemory();

        usageAsCollateralEnabled = liquidationThreshold > 0;
    }

    function getReserveData(address asset, bool reserveType)
        external
        view
        returns (
            uint256 availableLiquidity,
            uint256 totalVariableDebt,
            uint256 liquidityRate,
            uint256 variableBorrowRate,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            uint40 lastUpdateTimestamp
        )
    {
        DataTypes.ReserveData memory reserve =
            ILendingPool(ADDRESSES_PROVIDER.getLendingPool()).getReserveData(asset, reserveType);

        return (
            IERC20Detailed(asset).balanceOf(reserve.aTokenAddress),
            IERC20Detailed(reserve.variableDebtTokenAddress).totalSupply(),
            reserve.currentLiquidityRate,
            reserve.currentVariableBorrowRate,
            reserve.liquidityIndex,
            reserve.variableBorrowIndex,
            reserve.lastUpdateTimestamp
        );
    }

    function getUserReserveData(address asset, bool reserveType, address user)
        external
        view
        returns (
            uint256 currentATokenBalance,
            uint256 currentVariableDebt,
            uint256 scaledVariableDebt,
            uint256 liquidityRate,
            bool usageAsCollateralEnabled
        )
    {
        DataTypes.ReserveData memory reserve =
            ILendingPool(ADDRESSES_PROVIDER.getLendingPool()).getReserveData(asset, reserveType);

        DataTypes.UserConfigurationMap memory userConfig =
            ILendingPool(ADDRESSES_PROVIDER.getLendingPool()).getUserConfiguration(user);

        currentATokenBalance = IERC20Detailed(reserve.aTokenAddress).balanceOf(user);
        currentVariableDebt = IERC20Detailed(reserve.variableDebtTokenAddress).balanceOf(user);
        scaledVariableDebt =
            IVariableDebtToken(reserve.variableDebtTokenAddress).scaledBalanceOf(user);
        liquidityRate = reserve.currentLiquidityRate;
        usageAsCollateralEnabled = userConfig.isUsingAsCollateral(reserve.id);
    }

    function getReserveTokensAddresses(address asset, bool reserveType)
        external
        view
        returns (address aTokenAddress, address variableDebtTokenAddress)
    {
        DataTypes.ReserveData memory reserve =
            ILendingPool(ADDRESSES_PROVIDER.getLendingPool()).getReserveData(asset, reserveType);

        return (reserve.aTokenAddress, reserve.variableDebtTokenAddress);
    }
}