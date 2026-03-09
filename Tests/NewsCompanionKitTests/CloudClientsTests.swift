import Foundation
import Testing
@testable import NewsCompanionKit

@Suite("Cloud Clients Tests")
struct CloudClientsTests {

    @Test("AzureOpenAIClient can be created with nil additionalHeaders")
    func azureInitWithoutHeaders() {
        _ = AzureOpenAIClient(
            endpoint: "https://example.openai.azure.com",
            deployment: "gpt-4o-mini",
            apiKey: "test-key",
            timeout: 30,
            additionalHeaders: nil
        )
    }

    @Test("AzureOpenAIClient can be created with additionalHeaders")
    func azureInitWithHeaders() {
        _ = AzureOpenAIClient(
            endpoint: "https://example.openai.azure.com",
            deployment: "gpt-4o-mini",
            apiKey: "test-key",
            timeout: 30,
            additionalHeaders: ["x-ms-tenant-id": "tenant-1", "X-Custom": "value"]
        )
    }

    @Test("GoogleCloudVertexClient can be created with nil or non-nil additionalHeaders")
    func googleCloudInit() {
        _ = GoogleCloudVertexClient(
            project: "my-project",
            location: "us-central1",
            model: "gemini-1.5-flash",
            apiKey: "key",
            timeout: 30,
            additionalHeaders: nil
        )
        _ = GoogleCloudVertexClient(
            project: "my-project",
            location: "us-central1",
            model: "gemini-1.5-flash",
            apiKey: "key",
            timeout: 30,
            additionalHeaders: ["X-Request-ID": "test-id"]
        )
    }

    @Test("AWSBedrockClient can be created with endpoint or region, with nil or non-nil additionalHeaders")
    func awsBedrockInit() {
        _ = AWSBedrockClient(
            endpoint: "https://my-proxy.example.com",
            modelId: "anthropic.claude-3-sonnet-v1",
            apiKey: "key",
            timeout: 30,
            additionalHeaders: nil
        )
        _ = AWSBedrockClient(
            endpoint: "https://my-proxy.example.com",
            modelId: "anthropic.claude-3-sonnet-v1",
            apiKey: "key",
            timeout: 30,
            additionalHeaders: ["X-Tracing": "enabled"]
        )
        _ = AWSBedrockClient(
            region: "us-east-1",
            modelId: "anthropic.claude-3-sonnet-v1",
            apiKey: "",
            timeout: 30,
            additionalHeaders: ["Custom": "value"]
        )
    }

    @Test("Config stores additionalHeaders and makeAIClient uses them for Azure")
    func configAdditionalHeadersAzure() {
        let config = NewsCompanionKit.Config(
            apiKey: "key",
            provider: .azureOpenAI,
            model: "gpt-4o-mini",
            azureEndpoint: "https://example.openai.azure.com",
            additionalHeaders: ["x-ms-tenant-id": "tenant-1"]
        )
        let client = NewsCompanionKit.makeAIClient(config: config)
        #expect(client is AzureOpenAIClient)
    }

    @Test("Config additionalHeaders passed to makeAIClient for AWS Bedrock")
    func configAdditionalHeadersAWS() {
        let config = NewsCompanionKit.Config(
            apiKey: "key",
            provider: .awsBedrock,
            model: "anthropic.claude-3-sonnet-v1",
            awsRegion: "us-east-1",
            additionalHeaders: ["X-Custom": "value"]
        )
        let client = NewsCompanionKit.makeAIClient(config: config)
        #expect(client is AWSBedrockClient)
    }

    @Test("Config additionalHeaders passed to makeAIClient for Google Cloud Vertex")
    func configAdditionalHeadersGoogle() {
        let config = NewsCompanionKit.Config(
            apiKey: "key",
            provider: .googleCloudVertex,
            model: "gemini-1.5-flash",
            gcpProject: "my-project",
            gcpLocation: "us-central1",
            additionalHeaders: ["X-Request-ID": "id"]
        )
        let client = NewsCompanionKit.makeAIClient(config: config)
        #expect(client is GoogleCloudVertexClient)
    }

    @Test("Config with nil additionalHeaders still produces valid cloud clients")
    func configNilAdditionalHeaders() {
        let azureConfig = NewsCompanionKit.Config(
            apiKey: "k",
            provider: .azureOpenAI,
            azureEndpoint: "https://a.openai.azure.com",
            additionalHeaders: nil
        )
        #expect(NewsCompanionKit.makeAIClient(config: azureConfig) is AzureOpenAIClient)

        let awsConfig = NewsCompanionKit.Config(
            apiKey: "k",
            provider: .awsBedrock,
            awsRegion: "us-east-1",
            additionalHeaders: nil
        )
        #expect(NewsCompanionKit.makeAIClient(config: awsConfig) is AWSBedrockClient)

        let gcpConfig = NewsCompanionKit.Config(
            apiKey: "k",
            provider: .googleCloudVertex,
            gcpProject: "p",
            gcpLocation: "us-central1",
            additionalHeaders: nil
        )
        #expect(NewsCompanionKit.makeAIClient(config: gcpConfig) is GoogleCloudVertexClient)
    }
}
