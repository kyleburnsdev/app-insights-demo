# Mortgage Demo Solution for Azure Application Insights

## Purpose

This solution demonstrates a modern, cloud-native, microservices-based solution, designed to showcase Azure Application Insights, Azure Container Apps, Azure SQL Database, Azure Blob Storage, and Azure Load Testing. It is intended for learning, demonstration, and as a reference for best practices in observability, containerization, and secure cloud development.

Key features:

- Web UI for mortgage application submission and status tracking
- .NET (ASP.NET Core) Loan Processing Service
- Java (Spring Boot) Customer Service
- Azure SQL Database for persistent data
- Azure Blob Storage for document uploads
- All services containerized and deployed to Azure Container Apps
- Managed identities for secure resource access
- Application Insights for end-to-end observability
- Automated load testing and release annotations
- Infrastructure as Code (Bicep) and CI/CD (GitHub Actions)

---

## Solution Architecture

```mermaid
flowchart TD
    subgraph Azure
        ACR[Azure Container Registry]
        ACA[Azure Container Apps Environment]
        SQL[Azure SQL Database]
        Blob[Azure Blob Storage]
        AppInsights[Application Insights]
        LoadTest[Azure Load Testing]
    end

    subgraph ContainerApps
        UI[Web UI (React)]
        Loan[Loan Processing Service (.NET)]
        Cust[Customer Service (Java)]
    end

    User[User] --> UI
    UI --REST--> Loan
    UI --REST--> Cust
    Loan --SQL/Blob--> SQL
    Loan --Blob--> Blob
    Cust --SQL--> SQL

    UI -.->|Telemetry| AppInsights
    Loan -.->|Telemetry| AppInsights
    Cust -.->|Telemetry| AppInsights

    ACR -->|Images| UI
    ACR -->|Images| Loan
    ACR -->|Images| Cust

    LoadTest --> UI
    LoadTest --> Loan
    LoadTest --> Cust
```

---

## Deployment and Getting Started

### Prerequisites

- Azure subscription with sufficient quota for Container Apps, SQL, Storage, and Load Testing
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed and logged in
- [Docker](https://www.docker.com/products/docker-desktop) installed
- [GitHub account](https://github.com/) and permissions to create secrets in your fork
- [Java 17+](https://adoptium.net/) and [.NET 8 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/8.0) for local builds (optional)

### 1. Fork and Clone the Repository

```sh
git clone https://github.com/<your-username>/app-insights-demo.git
cd app-insights-demo
```

### 2. Set Up GitHub Secrets

In your forked repository, add the following secrets:

- `AZURE_CREDENTIALS`: Azure service principal credentials (JSON)
- `AZURE_CONTAINER_REGISTRY`: Your ACR login server (e.g., myregistry.azurecr.io)
- `AZURE_CONTAINER_REGISTRY_USERNAME` / `AZURE_CONTAINER_REGISTRY_PASSWORD`
- `AZURE_RESOURCE_GROUP`: Resource group for deployment
- `AZURE_LOCATION`: Azure region (e.g., eastus)
- `AZURE_SQL_ADMIN_USERNAME` / `AZURE_SQL_ADMIN_PASSWORD`
- `APPINSIGHTS_RESOURCE_NAME`: Name of your Application Insights resource

### 3. Review and Customize Infrastructure

- Edit `infra/main.bicep` if you want to change resource names, SKUs, or locations.
- Seed data for SQL and Blob Storage is in `infra/sql-seed.sql` and `infra/blob-seed/`.

### 4. Build and Push Images (CI/CD)

The GitHub Actions workflow (`.github/workflows/deploy.yml`) will:

- Build and push Docker images for each service to ACR
- Deploy infrastructure and container apps using Bicep
- Assign managed identity roles
- Run a smoke test using Azure Load Testing
- Annotate the release in Application Insights

You can trigger the workflow manually from the GitHub Actions UI or by pushing to `main`.

### 5. Monitor and Validate

- Use the Azure Portal to monitor Application Insights for telemetry, logs, and release annotations.
- Review the Azure Load Testing results for smoke test validation.
- Access the Web UI via the Container App FQDN (output in the deployment logs).

---

## Component Overview

```mermaid
graph TD
    subgraph Microservices
        A[Loan Processing Service (.NET)]
        B[Customer Service (Java)]
        C[Web UI (React)]
    end
    D[Azure SQL Database]
    E[Azure Blob Storage]
    F[Azure Container Apps]
    G[Application Insights]
    H[Azure Load Testing]

    A -- SQL/Blob --> D
    A -- Blob --> E
    B -- SQL --> D
    C -- REST --> A
    C -- REST --> B
    A -- Telemetry --> G
    B -- Telemetry --> G
    C -- Telemetry --> G
    F -- Hosts --> A
    F -- Hosts --> B
    F -- Hosts --> C
    H -- Test --> F
```

---

## Troubleshooting & Tips

- If a deployment step fails, check the GitHub Actions logs for details.
- Ensure all secrets are set and correct.
- For local development, you can build and run each service using Docker Compose or individual Docker commands.
- Health endpoints and readiness probes are implemented for all services.
- Managed identities are used for secure access to SQL and Blob Storage—no secrets in code.

---

## Contributing

Pull requests and issues are welcome! Please open an issue for bugs, questions, or feature requests.

---

## License

This project is for demonstration and educational purposes.

```text
MIT License
```
