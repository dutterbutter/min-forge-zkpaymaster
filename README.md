## Paymaster example usage


To use the script with paymaster already deployed to ZKsync Sepolia:

```
forge script script/Counter.s.sol:CounterScript \
  --rpc-url https://sepolia.era.zksync.dev \
  --broadcast \
  --account <YOUR-ACCOUNT> --sender <SENDER-ADDRESS> \
  -vvvv --zksync --gas-limit 10000000 --slow
```