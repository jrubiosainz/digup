# Microsoft Foundry – feature overview

*Contoso AI guild · study notes for the support agent pilot · checked against Microsoft Learn in October 2026*

Microsoft Foundry is Azure's platform for building AI apps and agents. One Azure resource brings agents, models and tools together, with tracing, monitoring and evaluations built in. You can drive it from the Foundry portal, the SDKs (Python, C#, JavaScript and Java), the Azure Developer CLI (`azd`) or VS Code.

## Where the name comes from

| When | What happened |
|---|---|
| November 2023 | **Azure AI Studio** enters public preview at Ignite |
| May 2024 | Azure AI Studio becomes generally available at Build |
| November 2024 | It evolves into **Azure AI Foundry** at Ignite |
| November 2025 | It is renamed **Microsoft Foundry** at Ignite, with a refreshed portal and a new icon |

## The building blocks

### Resources and projects

A single **Foundry resource with projects** replaces the older setup of a hub plus separate Azure OpenAI and Azure AI Services resources. Azure AI Services are now called **Foundry Tools**. Each project has one endpoint. In Python you talk to it with `azure-ai-projects` 2.x together with the OpenAI client, on the stable `/openai/v1/` routes instead of monthly API versions.

### Foundry Agent Service

The service that runs agents for you. It has been generally available since Build 2025. There are three kinds of agent:

- **Prompt agents**: instructions, a model and tools, defined declaratively.
- **Voice prompt agents**: prompt agents you talk to, through Voice Live.
- **Hosted agents**: your own code, built with Microsoft Agent Framework, LangGraph or CrewAI, packaged in a container that Foundry runs. You don't manage the infrastructure.

Conversations use the **Responses API** (conversations, responses and agent versions). It replaces the threads and runs of the Assistants API.

### Tools

- A catalog of **MCP** (Model Context Protocol) tools.
- **Toolboxes** (preview): one managed endpoint for tools, skills and MCP servers.
- The **`a2a`** tool type (Agent2Agent), generally available, for calling other agents.
- Function tools: your own functions, which the model asks your code to run.

### Models

- The **Foundry Models** catalog lists more than 10,000 models from Microsoft, OpenAI, Anthropic, Meta and others.
- **Model router**, generally available since Ignite 2025, picks the best model for each request behind a single endpoint.

### Knowledge: Foundry IQ

A managed knowledge layer that grounds agents in your data. It is built on Azure AI Search. Since Build 2026 it brings Work IQ, Fabric IQ, Azure SQL, File Search and MCP sources together behind one retrieval endpoint.

### Trust: guardrails, evaluations and tracing

- **Guardrails** (formerly content filters) are set per agent. They can step in on prompts, outputs, tool calls and tool responses, and they include a *task adherence* risk.
- **Evaluations** and **tracing** are built in. Since Build 2026 they also cover agents built with other frameworks (preview).
- **Foundry Control Plane** (preview) brings observability, guardrails and lifecycle management into one place. It builds on Microsoft Entra Agent ID, Microsoft Defender and Microsoft Purview.

### On your own machine

**Foundry Local** runs models on Windows and Mac, offline.

### Microsoft Agent Framework

An open-source SDK that unifies Semantic Kernel and AutoGen. Version 1.0 for .NET and Python shipped on April 3, 2026.

## What the pilot uses

- One project, `proj-support`, in Sweden Central, deployed with `azd up` (see `Code/contoso-support-agent`).
- A prompt agent with two function tools, `lookup_order` and `create_return`, plus File Search over our policy PDFs.
- An evaluation run over recorded conversations before every release (see *Agent evaluation checklist*).

## Sources

- What is Microsoft Foundry? – https://learn.microsoft.com/en-us/azure/ai-foundry/what-is-azure-ai-foundry
- What's new in Microsoft Foundry, October–November 2025 – https://devblogs.microsoft.com/foundry/whats-new-in-microsoft-foundry-oct-nov-2025/
- Ignite 2025 Book of News – https://news.microsoft.com/ignite-2025-book-of-news/
- What's new in Microsoft Foundry at Build 2026 – https://devblogs.microsoft.com/foundry/whats-new-in-microsoft-foundry-build-2026/
- Agent2Agent tool – https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent
- Microsoft Agent Framework 1.0 – https://devblogs.microsoft.com/agent-framework/microsoft-agent-framework-version-1-0/
