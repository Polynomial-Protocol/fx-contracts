pragma solidity >=0.8.11 <0.9.0;

interface IPythLazer {
    function verifyUpdate(bytes calldata update) external payable returns (bytes calldata payload, address signer);

    function verification_fee() external view returns (uint256);
}
