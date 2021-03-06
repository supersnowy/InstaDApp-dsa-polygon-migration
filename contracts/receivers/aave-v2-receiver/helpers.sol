pragma solidity >=0.7.0;
pragma experimental ABIEncoderV2;

import { DSMath } from "../../common/math.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Stores } from "../../common/stores-polygon.sol";
import { Variables } from "./variables.sol";

import {
    TokenMappingInterface,
    AaveData,
    AaveDataProviderInterface,
    AaveInterface,
    AccountInterface
} from "./interfaces.sol";

abstract contract Helpers is Stores, DSMath, Variables {
    using SafeERC20 for IERC20;

    struct TransferHelperData {
        address token;
        address atoken;
        uint atokenBal;
        uint supplyAmt;
        uint tokenLiq;
    }

    struct SpellHelperData {
        address token;
        address atoken;
        uint tokenLiq;
        uint borrowAmt;
    }

    function remapTokens(AaveData memory data) internal view returns (AaveData memory) {
        for (uint i = 0; i < data.supplyTokens.length; i++) {
            data.supplyTokens[i] = tokenMapping.getMapping(data.supplyTokens[i]);
        }

        for (uint i = 0; i < data.borrowTokens.length; i++) {
            data.borrowTokens[i] = tokenMapping.getMapping(data.borrowTokens[i]);
        }

        return data;
    }


    function isPositionSafe() internal view returns (bool isOk) {
        AaveInterface aave = AaveInterface(aaveProvider.getLendingPool());
        (,,,,,uint healthFactor) = aave.getUserAccountData(address(this));
        uint minLimit = wdiv(1e18, safeRatioGap);
        isOk = healthFactor > minLimit;
        require(isOk, "position-at-risk");
    }

    function transferAtokens(AaveInterface aave, address dsa, address[] memory supplyTokens, uint[] memory supplyAmts) internal {
        for (uint i = 0; i < supplyTokens.length; i++) {
            TransferHelperData memory data;
            data.token = supplyTokens[i] == maticAddr ? wmaticAddr : supplyTokens[i];
            (data.atoken, ,) = aaveData.getReserveTokensAddresses(data.token);
            IERC20 _atokenContract = IERC20(data.atoken);
            IERC20 _tokenContract = IERC20(data.token);
            data.atokenBal = _atokenContract.balanceOf(address(this));
            data.supplyAmt = supplyAmts[i];

            (data.tokenLiq,,,,,,,,,) = aaveData.getReserveData(data.token);

            if (data.atokenBal < data.supplyAmt) {
                uint _reqAmt = data.supplyAmt - data.atokenBal;
                uint num = _reqAmt/data.tokenLiq + 1;
                uint splitAmt = _reqAmt/num;
                uint finalSplit = _reqAmt - (splitAmt * (num - 1));

                _tokenContract.approve(address(aave), _reqAmt);
                for (uint j = 0; j < num; j++) {
                    if (j < num - 1) {
                        aave.borrow(data.token, splitAmt, 2, 3288, address(this));
                        aave.deposit(data.token, splitAmt, address(this), 3288);
                        if (j == 0) aave.setUserUseReserveAsCollateral(data.token, true);
                    } else {
                        aave.borrow(data.token, finalSplit, 2, 3288, address(this));
                        aave.deposit(data.token, finalSplit, address(this), 3288);
                    }
                }
            }

            _atokenContract.safeTransfer(dsa, data.supplyAmt);
        }
    }

    function borrowAndTransferSpells(address dsa, address[] memory supplyTokens, address[] memory borrowTokens, uint[] memory borrowAmts) internal {
        for (uint i = 0; i < borrowTokens.length; i++) {
            SpellHelperData memory data;
            data.token = borrowTokens[i] == maticAddr ? wmaticAddr : borrowTokens[i];
            (data.atoken, ,) = aaveData.getReserveTokensAddresses(data.token);
            (data.tokenLiq,,,,,,,,,) = aaveData.getReserveData(data.token);
            data.borrowAmt = borrowAmts[i];

            uint num = data.borrowAmt/data.tokenLiq + 1;
            uint splitAmt = data.borrowAmt/num;
            uint finalSplit = data.borrowAmt - (splitAmt * (num - 1));

            uint spellsAmt = num <= 1 ? (2 * (num + 1)) : (2 * (num + 1)) + 1;
            string[] memory targets = new string[](spellsAmt);
            bytes[] memory castData = new bytes[](spellsAmt);

            targets[0] = "AAVE-V2-A";
            castData[0] = abi.encodeWithSignature("enableCollateral(address[])", supplyTokens);
                    
            for (uint j = 0; j < num; j++) {
                uint k = j * 2 + 1;
                
                if (i < num - 1) {
                    targets[k] = "AAVE-V2-A";
                    castData[k] = abi.encodeWithSignature("borrow(address,uint256,uint256,uint256,uint256)", data.token, splitAmt, 2, 0, 0);
                    targets[k+1] = "AAVE-V2-A";
                    castData[k+1] = abi.encodeWithSignature("deposit(address,uint256,uint256,uint256)", data.token, splitAmt, 0, 0);
                } else {
                    targets[k] = "AAVE-V2-A";
                    castData[k] = abi.encodeWithSignature("borrow(address,uint256,uint256,uint256,uint256)", data.token, finalSplit, 2, 0, 0);
                    targets[k+1] = "AAVE-V2-A";
                    castData[k+1] = abi.encodeWithSignature("deposit(address,uint256,uint256,uint256)", data.token, finalSplit, 0, 0);
                }
            }

            targets[spellsAmt - 1] = "BASIC-A";
            castData[spellsAmt - 1] = abi.encodeWithSignature("withdraw(address,uint256,address,uint256,uint256)", data.atoken, data.borrowAmt, address(this), 0, 0); // encode the data of atoken withdrawal
            AccountInterface(dsa).castMigrate(targets, castData, address(this));
        }

    }

}
