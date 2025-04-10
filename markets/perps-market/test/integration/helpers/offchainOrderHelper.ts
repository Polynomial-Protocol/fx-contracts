import { ethers, BigNumber } from 'ethers';
import { ecsign } from 'ethereumjs-util';
import { DEFAULT_SETTLEMENT_STRATEGY } from '../bootstrap';

export interface Order {
  marketId: BigNumber;
  accountId: BigNumber;
  sizeDelta: BigNumber;
  settlementStrategyId: number;
  referrerOrRelayer: string;
  limitOrderMaker: boolean;
  allowAggregation: boolean;
  allowPartialMatching: boolean;
  timestamp: number;
  acceptablePrice: BigNumber;
  trackingCode: string;
  expiration: number;
  nonce: number;
}

interface CancelOrderRequest {
  accountId: number;
  nonce: number;
}

interface OrderCreationArgs {
  accountId: number;
  isShort: boolean;
  isMaker: boolean;
  marketId: BigNumber;
  relayer: string;
  amount: BigNumber;
  price: BigNumber;
  expiration: number;
  nonce: number;
  trackingCode: string;
}

async function getDomain(signer: ethers.Wallet, contractAddress: string): Promise<string> {
  const chainId = await signer.getChainId();

  return ethers.utils.keccak256(
    ethers.utils.defaultAbiCoder.encode(
      ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'],
      [
        ethers.utils.keccak256(
          ethers.utils.toUtf8Bytes(
            'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
          )
        ),
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes('PolynomialPerpetualFutures')),
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes('1')),
        chainId,
        contractAddress,
      ]
    )
  );
}

export function createOrder(orderArgs: OrderCreationArgs): Order {
  const {
    accountId,
    marketId,
    relayer,
    isShort,
    amount,
    price,
    isMaker,
    expiration,
    nonce,
    trackingCode,
  } = orderArgs;
  return {
    marketId,
    accountId: BigNumber.from(accountId),
    sizeDelta: isShort ? amount.abs().mul(-1) : amount.abs(),
    settlementStrategyId: DEFAULT_SETTLEMENT_STRATEGY.strategyType,
    referrerOrRelayer: relayer,
    limitOrderMaker: isMaker,
    allowAggregation: false,
    allowPartialMatching: true,
    timestamp: Math.floor(Date.now() / 1000),
    acceptablePrice: price,
    trackingCode,
    expiration,
    nonce,
  };
}

const ORDER_TYPEHASH = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes(
    'OffchainOrder(uint128 marketId,uint128 accountId,int128 sizeDelta,uint128 settlementStrategyId,address referrerOrRelayer,bool allowAggregation,bool allowPartialMatching,uint256 acceptablePrice,bytes32 trackingCode,uint256 expiration,uint256 nonce)'
  )
);

const CANCEL_ORDER_TYPEHASH = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes('CancelOrderRequest(uint128 accountId,uint256 nonce)')
);

export async function signOrder(
  order: Order,
  signer: ethers.Wallet,
  contractAddress: string
): Promise<{ v: number; r: Buffer; s: Buffer }> {
  const domainSeparator = await getDomain(signer, contractAddress);

  const digest = ethers.utils.keccak256(
    ethers.utils.solidityPack(
      ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
      [
        '0x19',
        '0x01',
        domainSeparator,
        ethers.utils.keccak256(
          ethers.utils.defaultAbiCoder.encode(
            [
              'bytes32',
              'uint128',
              'uint128',
              'int128',
              'uint128',
              'address',
              'bool',
              'bool',
              'uint256',
              'bytes32',
              'uint256',
              'uint256',
            ],
            [
              ORDER_TYPEHASH,
              order.marketId,
              order.accountId,
              order.sizeDelta,
              order.settlementStrategyId,
              order.referrerOrRelayer,
              order.allowAggregation,
              order.allowPartialMatching,
              order.acceptablePrice,
              order.trackingCode,
              order.expiration,
              order.nonce,
            ]
          )
        ),
      ]
    )
  );

  return ecsign(
    Buffer.from(digest.slice(2), 'hex'),
    Buffer.from(signer.privateKey.slice(2), 'hex')
  );
}

export async function signCancelOrderRequest(
  cancelOrderRequest: CancelOrderRequest,
  signer: ethers.Wallet,
  contractAddress: string
): Promise<{ v: number; r: Buffer; s: Buffer }> {
  const domainSeparator = await getDomain(signer, contractAddress);

  const digest = ethers.utils.keccak256(
    ethers.utils.solidityPack(
      ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
      [
        '0x19',
        '0x01',
        domainSeparator,
        CANCEL_ORDER_TYPEHASH,
        ethers.utils.solidityPack(
          ['uint128', 'uint256'],
          [cancelOrderRequest.accountId, cancelOrderRequest.nonce]
        ),
      ]
    )
  );

  return ecsign(
    Buffer.from(digest.slice(2), 'hex'),
    Buffer.from(signer.privateKey.slice(2), 'hex')
  );
}
