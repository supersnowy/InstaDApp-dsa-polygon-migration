pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TokenInterface, AccountInterface } from "../../common/interfaces.sol";
import { AaveInterface, ReceiverInterface, AaveData } from "./interfaces.sol";
import { Helpers } from "./helpers.sol";
import { Events } from "./events.sol";

contract AaveMigratorResolver is Helpers, Events {
    using SafeERC20 for IERC20;

    ReceiverInterface public immutable receiver;

    constructor(address _receiver) {
        receiver = ReceiverInterface(_receiver);
    }

    function migrateAave(address owner) external payable returns (bytes32) {
        require(msg.sender == address(receiver) && AccountInterface(address(this)).isAuth(owner), "not-authorized");
        AaveData memory data = receiver.getPosition(owner);
        require(!data.isFinal, "already-migrated");

        AaveInterface aave = AaveInterface(aaveProvider.getLendingPool());

        for (uint i = 0; i < data.supplyTokens.length; i++) {
            TokenInterface token = TokenInterface(data.supplyTokens[i]);
            uint amt = data.supplyAmts[i];
            token.approve(address(aave), amt);

            aave.deposit(address(token), amt, address(this), referralCode);
            if (!getIsColl(address(token))) {
                aave.setUserUseReserveAsCollateral(address(token), true);
            }
        }

        for (uint i = 0; i < data.borrowTokens.length; i++) {
            address token = data.borrowTokens[i];
            uint variableAmt = data.variableBorrowAmts[i];
            uint stableAmt = data.stableBorrowAmts[i];

            if (variableAmt > 0) {
                aave.borrow(token, variableAmt, 2, referralCode, address(this));
            }
            if (stableAmt > 0) {
                aave.borrow(token, stableAmt, 1, referralCode, address(this));
            }

            uint totalAmt = add(variableAmt, stableAmt);
            IERC20(token).safeTransfer(address(receiver), totalAmt);
        }
    }
}