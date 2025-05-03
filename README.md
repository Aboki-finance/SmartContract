# SimpleGateway System: Complete User Guide

## Overview

The SimpleGateway system is a modular token exchange platform that allows users to create orders for token exchanges at specified rates. This guide covers the key components, functionality, and how to interact with the system.

## System Components

### 1. SimpleGateway

The main contract that users interact with to:
- Create exchange orders
- Check order status
- Process or cancel orders

### 2. SimpleAggregator

The "brain" of the system that:
- Calculates exchange rates
- Determines if orders should be fulfilled
- Executes token transfers

### 3. MockToken

A test ERC20 token for development purposes.

## How It Works

![System Diagram](https://via.placeholder.com/800x400?text=SimpleGateway+System+Flow)

### Basic Flow:

1. **User creates an order** with source token, target token, amount and expected rate
2. **Gateway holds the funds** and assigns a unique order ID
3. **Processor calls the gateway** to process the order
4. **Aggregator determines current rate** and decides whether to fulfill
5. **Order is either fulfilled** (tokens exchanged) or **refunded** (original tokens returned)

## User Functions

### Creating an Order

Users deposit tokens and specify their desired exchange parameters:

```javascript
gateway.createOrder(
  sourceTokenAddress,  // Token you're sending
  targetTokenAddress,  // Token you want to receive
  amount,              // Amount of source tokens
  expectedRate         // Minimum exchange rate you'll accept
)
```

**Example:**
```javascript
// Creating an order to exchange 100 TokenA for TokenB at a rate of at least 1:0.5
const tx = await gateway.createOrder(
  tokenA.address,
  tokenB.address,
  ethers.utils.parseEther("100"),
  ethers.utils.parseEther("0.5")
);
```

### Checking Order Status

Users can check the status of their orders:

```javascript
gateway.getOrder(orderId)
```

**Order Status:**
- `0` = Pending (awaiting processing)
- `1` = Fulfilled (exchange completed)
- `2` = Refunded (original tokens returned)

### Cancelling an Order

Orders can be cancelled if they're still pending:

```javascript
gateway.cancelOrder(orderId)
```

## Administrator Functions

### Processing Orders

Authorized processors can initiate order processing:

```javascript
gateway.processOrder(orderId)
```

### Setting the Aggregator

Admin can update which aggregator is used:

```javascript
gateway.setAggregator(aggregatorAddress)
```

## Rate Determination

The SimpleAggregator determines the exchange rate between tokens. For simplicity in this implementation:

- Rate checks compare the expected rate against the current rate
- Orders are fulfilled if the current rate is equal to or better than the expected rate
- Otherwise, orders are refunded

## Common Scenarios

### Successful Exchange

1. User creates order with 100 TokenA for TokenB at 1:0.5 rate
2. Current rate is 1:0.6 (better than requested)
3. Order is fulfilled, user receives 60 TokenB

### Failed Exchange

1. User creates order with 100 TokenA for TokenB at 1:0.5 rate
2. Current rate is 1:0.4 (worse than requested)
3. Order is refunded, user receives their 100 TokenA back

## Deployment & Integration

### Contract Deployment Order

For proper system setup, deploy in this order:
1. Deploy MockToken (for testing)
2. Deploy SimpleGateway
3. Deploy SimpleAggregator with gateway address
4. Set the aggregator in the gateway

### Code Example: Full Integration Flow

```javascript
// 1. Deploy contracts
const MockToken = await ethers.getContractFactory("MockToken");
const mockToken = await MockToken.deploy("TestToken", "TTK");

const SimpleGateway = await ethers.getContractFactory("SimpleGateway");
const gateway = await SimpleGateway.deploy();

const SimpleAggregator = await ethers.getContractFactory("SimpleAggregator");
const aggregator = await SimpleAggregator.deploy(gateway.address);

// 2. Set aggregator in gateway
await gateway.setAggregator(aggregator.address);

// 3. Mint tokens for testing
await mockToken.mint(userAddress, ethers.utils.parseEther("1000"));

// 4. Approve tokens for gateway
await mockToken.approve(gateway.address, ethers.utils.parseEther("100"));

// 5. Create an order
const tx = await gateway.createOrder(
  mockToken.address,
  mockToken.address,
  ethers.utils.parseEther("100"),
  ethers.utils.parseEther("1")
);
const receipt = await tx.wait();

// 6. Get order ID from event
const event = receipt.events.find(e => e.event === 'OrderCreated');
const orderId = event.args.orderId;

// 7. Process the order
await gateway.processOrder(orderId);

// 8. Check order status
const order = await gateway.getOrder(orderId);
console.log("Order status:", order.status);
```

## Security Considerations

- **Token Approval**: Always approve only the exact amount needed
- **Rate Checking**: Verify expected rates carefully before creating orders
- **Status Verification**: Always check order status after processing

## Troubleshooting

### Common Issues

**Issue**: Transaction reverts when creating order
**Solution**: Ensure you've approved enough tokens for the gateway

**Issue**: Order processing fails
**Solution**: Check that the aggregator is properly set in the gateway

**Issue**: Unexpected exchange rate
**Solution**: Verify the rate calculation in the aggregator contract

## Conclusion

The SimpleGateway system provides a flexible way to create token exchange orders with rate protection. By separating order management from rate determination, it maintains a clean architecture that can be extended for more complex exchange scenarios.

For additional support or custom implementations, refer to the contract documentation or contact the development team.
npm run deploy
# or
yarn deploy
```

> [!IMPORTANT]
> This requires a secret key to make it work. Get your secret key [here](https://thirdweb.com/dashboard/settings/api-keys).
> Pass your secret key as a value after `-k` flag.
> ```bash
> npm run deploy -- -k <your-secret-key>
> # or
> yarn deploy -k <your-secret-key>

## Releasing Contracts

If you want to release a version of your contracts publicly, you can use one of the followings command:

```bash
npm run release
# or
yarn release
```
