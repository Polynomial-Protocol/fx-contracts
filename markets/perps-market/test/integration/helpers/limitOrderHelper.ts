import { ethers, BigNumber } from 'ethers';
import { ecsign } from 'ethereumjs-util';

export interface Order {
  accountId: number;
  marketId: BigNumber;
  relayer: string;
  amount: BigNumber;
  price: BigNumber;
  limitOrderMaker: boolean;
  expiration: number;
  nonce: number;
  allowPartialMatching: boolean;
  trackingCode: string;
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

function createLimitOrder(orderArgs: OrderCreationArgs): Order {
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
    accountId,
    marketId,
    relayer,
    amount: isShort ? amount.abs().mul(-1) : amount.abs(),
    price,
    limitOrderMaker: isMaker,
    expiration,
    nonce,
    allowPartialMatching: false,
    trackingCode,
  };
}

export function createMatchingLimitOrders(orderArgs: OrderCreationArgs): {
  shortOrder: Order;
  longOrder: Order;
} {
  if (orderArgs.amount.lt(0) || orderArgs.isShort) {
    throw new Error('arguments must be for the long position for this method to work');
  }
  const order = createLimitOrder(orderArgs);
  const oppositeOrder = createLimitOrder({
    ...orderArgs,
    isShort: true,
    accountId: orderArgs.accountId - 1,
    isMaker: !orderArgs.isMaker,
  });
  return {
    shortOrder: oppositeOrder,
    longOrder: order,
  };
}

const ORDER_TYPEHASH = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes(
    'SignedOrderRequest(uint128 accountId,uint128 marketId,address relayer,int128 amount,uint256 price,uint256 expiration,uint256 nonce,bytes32 trackingCode,bool allowPartialMatching)'
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
  const {
    accountId,
    marketId,
    relayer,
    amount,
    price,
    expiration,
    nonce,
    allowPartialMatching,
    trackingCode,
  } = order;
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
              'address',
              'int128',
              'uint256',
              'uint256',
              'uint256',
              'bytes32',
              'bool',
            ],
            [
              ORDER_TYPEHASH,
              accountId,
              marketId,
              relayer,
              amount,
              price,
              expiration,
              nonce,
              trackingCode,
              allowPartialMatching,
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
  order: CancelOrderRequest,
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
            ['bytes32', 'uint128', 'uint256'],
            [CANCEL_ORDER_TYPEHASH, order.accountId, order.nonce]
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
