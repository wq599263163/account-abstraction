// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable no-inline-assembly */

// 参考文档：
// https://medium.com/infinitism/erc-4337-account-abstraction-without-ethereum-protocol-changes-d75c9d94dc4a
/**
*用户操作结构
*@param sender 本次请求的发起人钱包地址
*@param nonce 发送者用来验证它不是重播的唯一值。和我们之前钱包的 nonce 值一样，会按照 nonce 严格执行
*@param initCode 如果设置，账户合约将由此构造函数创建，如果钱包尚不存在，则用于创建钱包的初始化代码
*@param callData 要在此帐户上执行的方法调用，实际执行步骤用什么数据调用钱包
*@param verificationGasLimit gas 用于 validateUserOp 和 validatePaymasterUserOp
*@param preVerificationGas gas 不是通过 handleOps 方法计算的，而是添加到支付的 gas 中。涵盖批量开销。
*@param maxFeePerGas 与 EIP-1559 gas 参数相同
*@param maxPriorityFeePerGas 与 EIP-1559 gas 参数相同
*@param paymasterAndData 如果设置，该字段保存付款人地址和“付款人特定数据”。出纳员将代替发件人支付交易费用
*@param signature 对整个请求、EntryPoint 地址和链 ID 的发件人验证签名。
*/
struct UserOperation {

    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    uint256 callGasLimit;
    uint256 verificationGasLimit;
    uint256 preVerificationGas;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    bytes paymasterAndData;
    bytes signature;
}

library UserOperationLib {

    function getSender(UserOperation calldata userOp) internal pure returns (address) {
        address data;
        //read sender from userOp, which is first userOp member (saves 800 gas...)
        assembly {data := calldataload(userOp)}
        return address(uint160(data));
    }

    //relayer/block builder might submit the TX with higher priorityFee, but the user should not
    // pay above what he signed for.
    function gasPrice(UserOperation calldata userOp) internal view returns (uint256) {
    unchecked {
        uint256 maxFeePerGas = userOp.maxFeePerGas;
        uint256 maxPriorityFeePerGas = userOp.maxPriorityFeePerGas;
        if (maxFeePerGas == maxPriorityFeePerGas) {
            //legacy mode (for networks that don't support basefee opcode)
            return maxFeePerGas;
        }
        return min(maxFeePerGas, maxPriorityFeePerGas + block.basefee);
    }
    }

    function pack(UserOperation calldata userOp) internal pure returns (bytes memory ret) {
        //lighter signature scheme. must match UserOp.ts#packUserOp
        bytes calldata sig = userOp.signature;
        // copy directly the userOp from calldata up to (but not including) the signature.
        // this encoding depends on the ABI encoding of calldata, but is much lighter to copy
        // than referencing each field separately.
        assembly {
            let ofs := userOp
            let len := sub(sub(sig.offset, ofs), 32)
            ret := mload(0x40)
            mstore(0x40, add(ret, add(len, 32)))
            mstore(ret, len)
            calldatacopy(add(ret, 32), ofs, len)
        }
    }

    function hash(UserOperation calldata userOp) internal pure returns (bytes32) {
        return keccak256(pack(userOp));
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
