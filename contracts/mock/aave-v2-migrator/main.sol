pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import { Variables } from "./variables.sol";

/**
 * @title InstaAccountV2 Implementation-M2.
 * @dev DeFi Smart Account Wallet for polygon migration.
 */

interface ConnectorsInterface {
    function isConnectors(string[] calldata connectorNames) external view returns (bool, address[] memory);
}

contract Constants is Variables {
    // InstaIndex Address.
    address internal constant instaIndex = 0xA9B99766E6C676Cf1975c0D3166F96C0848fF5ad;
    // Migration contract Address.
    address internal constant migrationContract = 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9;
    // Connnectors Address.
    address public constant connectorsM1 = 0x0a0a82D2F86b9E46AE60E22FCE4e8b916F858Ddc;
}

contract InstaImplementationM2 is Constants {

    function decodeEvent(bytes memory response) internal pure returns (string memory _eventCode, bytes memory _eventParams) {
        if (response.length > 0) {
            (_eventCode, _eventParams) = abi.decode(response, (string, bytes));
        }
    }

    event LogCastMigrate(
        address indexed origin,
        address indexed sender,
        uint256 value,
        string[] targetsNames,
        address[] targets,
        string[] eventNames,
        bytes[] eventParams
    );

    receive() external payable {}

     /**
     * @dev Delegate the calls to Connector.
     * @param _target Connector address
     * @param _data CallData of function.
    */
    function spell(address _target, bytes memory _data) internal returns (bytes memory response) {
        require(_target != address(0), "target-invalid");
        assembly {
            let succeeded := delegatecall(gas(), _target, add(_data, 0x20), mload(_data), 0, 0)
            let size := returndatasize()
            
            response := mload(0x40)
            mstore(0x40, add(response, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            mstore(response, size)
            returndatacopy(add(response, 0x20), 0, size)

            switch iszero(succeeded)
                case 1 {
                    // throw if delegatecall failed
                    returndatacopy(0x00, 0x00, size)
                    revert(0x00, size)
                }
        }
    }

    /**
     * @dev This is the main function, Where all the different functions are called
     * from Smart Account.
     * @param _targetNames Array of Connector address.
     * @param _datas Array of Calldata.
    */
    function castMigrate(
        string[] calldata _targetNames,
        bytes[] calldata _datas,
        address _origin
    )
    external
    payable 
    returns (bytes32) // Dummy return to fix instaIndex buildWithCast function
    {   
        uint256 _length = _targetNames.length;
        require(msg.sender == migrationContract, "2: permission-denied");
        require(_length != 0, "2: length-invalid");
        require(_length == _datas.length , "2: array-length-invalid");

        string[] memory eventNames = new string[](_length);
        bytes[] memory eventParams = new bytes[](_length);

        // TODO: restrict migration contract to run something specific? or give is all access as it doesn't have power to run anything else
        (bool isOk, address[] memory _targets) = ConnectorsInterface(connectorsM1).isConnectors(_targetNames);

        require(isOk, "2: not-connector");

        for (uint i = 0; i < _length; i++) {
            bytes memory response = spell(_targets[i], _datas[i]);
            (eventNames[i], eventParams[i]) = decodeEvent(response);
        }

        emit LogCastMigrate(
            _origin,
            msg.sender,
            msg.value,
            _targetNames,
            _targets,
            eventNames,
            eventParams
        );
    }

}