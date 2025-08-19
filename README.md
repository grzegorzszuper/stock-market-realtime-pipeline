# stock-market-realtime-pipeline
flowchart LR
  %% --- Left side (client) ---
  U[User]
  P1["(1) Python Script<br/>(sends real-time stock data)"]

  U --> P1
  P1 -->|"sends real-time stock data"| K2["(2) Amazon Kinesis Data Streams"]

  %% --- AWS Cloud block ---
  subgraph AWS_Cloud [AWS Cloud]
    K2 -->|"Trigger"| L3["(3) AWS Lambda"]

    %% S3 / Glue / Athena path
    L3 -->|"Store raw data"| S4["(4) Amazon S3"]
    S4 -->|"Schema & data is structured"| G5["(5) AWS Glue Data Catalog"]
    G5 -->|"Query"| A6["(6) Amazon Athena"]
    A6 -->|"Store query results"| S7["(7) Amazon S3"]

    %% DynamoDB / Trends / SNS path
    L3 -->|"Store processed data"| D8["(8) Amazon DynamoDB"]
    D8 -->|"Trigger"| LT9["(9) AWS Lambda"]
    LT9 -->|"Notify trends"| N10["(10) Amazon SNS"]
  end
