# Bedrock curl test

Test that AWS Bedrock returns **200** with the same request shape the app uses.

**Prereqs:** `pip install awscurl`, then configure AWS (`aws configure` or env vars).

```bash
./test_bedrock_curl.sh          # default region us-east-1
./test_bedrock_curl.sh us-west-2
```

When you see **OK: statusCode 200**, the `AWSBedrockClient` implementation is aligned: it uses the same URL (`.../model/<modelId>/invoke`), body (Llama `prompt`, `max_gen_len`, `temperature`, `top_p`), and parses the response `generation` field.
