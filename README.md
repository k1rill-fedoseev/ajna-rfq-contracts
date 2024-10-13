# Ajna RFQ orders for secondary lenders LP position market

**DISCLAIMER:** This smart contract is provided "as is" and has not undergone a formal security audit. Use at your own
risk. The developers are not liable for any losses, damages, or vulnerabilities that may arise from using this contract.
Users are advised to review the code and perform their own security assessments before interacting with the contract.

## How it works

Whenever Ajna lenders can't or don't want to use the primary market for exiting their LP positions, they can instead set
up an RFQ order for selling their position with a small discount to the primary market.

Setting up an order involves few steps:

1. Approve an RFQ contract to transfer LP on behalf of the maker.
2. Sign an EIP-712 order message with ECDSA/ERC-1271 signature.
3. Send the order information to the off-chain order book.
4. Wait for takers to come and fill the order.

Protocol also support inverse orders, where maker sets an RFQ order to buy Ajna LP in the particular pool with discount
using their quote tokens. In such orders, takers will be the ones selling their Ajna LP shares.

### Ajna LP approval

Approving Ajna LP shares involves two steps:
1. Call `approveLPTransferors` (required once for Ajna pool)
2. Call `increaseLPAllowance` (required after each LP transfer, e.g. after each partial fill)

### Manual order signing

```shell
$ cat order.json
{
  "types": {
    "EIP712Domain": [
      {
        "name": "name",
        "type": "string"
      },
      {
        "name": "version",
        "type": "string"
      },
      {
        "name": "chainId",
        "type": "uint256"
      },
      {
        "name": "verifyingContract",
        "type": "address"
      }
    ],
    "Order": [
      {
        "name": "lpOrder",
        "type": "bool"
      },
      {
        "name": "maker",
        "type": "address"
      },
      {
        "name": "taker",
        "type": "address"
      },
      {
        "name": "pool",
        "type": "address"
      },
      {
        "name": "index",
        "type": "uint256"
      },
      {
        "name": "makeAmount",
        "type": "uint256"
      },
      {
        "name": "minMakeAmount",
        "type": "uint256"
      },
      {
        "name": "expiry",
        "type": "uint256"
      },
      {
        "name": "price",
        "type": "uint256"
      }
    ]
  },
  "primaryType": "Order",
  "domain": {
    "name": "Ajna RFQ",
    "version": "1",
    "chainId": 8453,
    "verifyingContract": "0xb6a68453b6509173836c20b4BcF66c139ca5CA3F"
  },
  "message": {
    "lpOrder": true,
    "maker": "0xD768aC37fe5A4c64121462Fc98205a7129c1198a",
    "taker": "0x0000000000000000000000000000000000000000",
    "pool": "0x0B17159F2486f669a1F930926638008E2ccB4287",
    "index": 2619,
    "makeAmount": 1045428212896713652,
    "minMakeAmount": 1045428212896713652,
    "expiry": 2000000000,
    "price": 990000000000000000
  }
}
$ cast wallet sign --private-key $PRIVATE_KEY --data --from-file order.json
0xd93de85a734abeb7954f629fd80428dbbe4e3615aa0543a8efbc7dc1cf3495660d8882562562c67d33d96718779e9368c3eb7b20dcc54747abe2ceb20bd204bf1b
```

## Deployment addresses

The `AjnaRFQ` contract is deployed on Base on `0xb6a68453b6509173836c20b4BcF66c139ca5CA3F`

## Funding

Initial development was fully funded by the Ajna grant of `800,000 AJNA`.
See [this](https://forum.ajna.finance/t/secondary-on-chain-market-for-ajna-lenders/235) for more details.
Thanks to Ajna community for supporting this project.