pragma solidity ^0.7.0;

import { MemoryInterface } from "./interfaces.sol";


abstract contract Stores {

    /**
    * @dev Return ethereum address
    * ETH on Mainnet
    * MATIC on Polygon
    */
    address constant internal ethAddr = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /**
    * @dev Return Wrapped ETH address
    */
    address constant internal wethAddr = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /**
    * @dev Return memory variable address
    */
    MemoryInterface constant internal instaMemory = MemoryInterface(0x8a5419CfC711B2343c17a6ABf4B2bAFaBb06957F);

    /**
    * @dev Get Uint value from InstaMemory Contract.
    */
    function getUint(uint getId, uint val) internal returns (uint returnVal) {
        returnVal = getId == 0 ? val : instaMemory.getUint(getId);
    }

    /**
    * @dev Set Uint value in InstaMemory Contract.
    */
    function setUint(uint setId, uint val) virtual internal {
        if (setId != 0) instaMemory.setUint(setId, val);
    }

}
