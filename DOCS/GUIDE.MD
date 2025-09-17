# DanpheEMR Docker Setup for Render Deployment

## 📋 Project Analysis
Based on your project structure and setup guide:
- **Backend**: .NET Core 3.1.301 (ASP.NET Core)
- **Frontend**: Angular 7+ (in `wwwroot/DanpheApp`)
- **Database**: MS SQL Server (external service recommended)
- **File Structure**: Solution in `Code/Solutions/DanpheEMR.sln`

## 🐳 Single Container Dockerfile

Create this `Dockerfile` in your **root directory**:

```dockerfile
# Multi-stage build for DanpheEMR on Render
FROM node:14-alpine AS angular-build

# Set working directory for Angular build
WORKDIR /app/frontend

# Install Angular CLI 7 globally
RUN npm install -g @angular/cli@7

# Copy Angular project files
COPY Code/Websites/DanpheEMR/wwwroot/DanpheApp/package*.json ./
RUN npm install --legacy-peer-deps

# Copy Angular source code
COPY Code/Websites/DanpheEMR/wwwroot/DanpheApp/ ./

# Build Angular application
RUN ng build --prod --output-path=dist --base-href=/

# Stage 2: Build .NET Core application
FROM mcr.microsoft.com/dotnet/sdk:3.1.301 AS dotnet-build

WORKDIR /src

# Copy solution and project files for better caching
COPY Code/Solutions/DanpheEMR.sln ./
COPY Code/Solutions/global.json ./

# Copy all project files (adjust paths based on your structure)
COPY Code/Websites/DanpheEMR/ ./DanpheEMR/

# Restore NuGet packages
RUN dotnet restore DanpheEMR/DanpheEMR.csproj

# Build and publish the application
RUN dotnet publish DanpheEMR/DanpheEMR.csproj -c Release -o /app/publish --no-restore

# Stage 3: Final runtime image
FROM mcr.microsoft.com/dotnet/aspnet:3.1 AS final

WORKDIR /app

# Install curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Create directories for file uploads and logs
RUN mkdir -p /app/uploads/LabReports /app/logs /app/credentials

# Copy published .NET application
COPY --from=dotnet-build /app/publish ./

# Copy built Angular files to wwwroot
RUN mkdir -p wwwroot/DanpheApp
COPY --from=angular-build /app/frontend/dist ./wwwroot/DanpheApp/

# Copy database scripts (optional, for reference)
COPY Database/ ./Database/

# Create appsettings for production
COPY appsettings.Production.json ./appsettings.Production.json

# Set environment variables
ENV ASPNETCORE_ENVIRONMENT=Production
ENV ASPNETCORE_URLS=http://+:$PORT
ENV TZ=UTC

# Create non-root user for security
RUN groupadd -r danphe && useradd -r -g danphe danphe
RUN chown -R danphe:danphe /app
USER danphe

# Expose port (Render will set $PORT environment variable)
EXPOSE $PORT

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:$PORT/health || exit 1

# Start the application
ENTRYPOINT ["dotnet", "DanpheEMR.dll"]
```

## ⚙️ Configuration Files

### 1. Create `appsettings.Production.json`

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Server=tcp:${AZURE_SQL_SERVER}.database.windows.net,1433;Initial Catalog=DanpheEMR_OS;Persist Security Info=False;User ID=${AZURE_SQL_USER};Password=${AZURE_SQL_PASSWORD};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;",
    "AdminConnection": "Server=tcp:${AZURE_SQL_SERVER}.database.windows.net,1433;Initial Catalog=DanpheAdmin;Persist Security Info=False;User ID=${AZURE_SQL_USER};Password=${AZURE_SQL_PASSWORD};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;",
    "AuditConnection": "Server=tcp:${AZURE_SQL_SERVER}.database.windows.net,1433;Initial Catalog=DanpheAudit;Persist Security Info=False;User ID=${AZURE_SQL_USER};Password=${AZURE_SQL_PASSWORD};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft": "Warning",
      "Microsoft.Hosting.Lifetime": "Information"
    }
  },
  "AllowedHosts": "*",
  "ServiceAccountKey": "/app/credentials/credentials.json",
  "LoggerFilePath": "/app/logs",
  "UploadFileBasePath": "/app/uploads/LabReports",
  "CORS": {
    "AllowedOrigins": ["https://your-render-app.onrender.com"]
  }
}
```

### 2. Create `.dockerignore`

```dockerignore
# Git
.git
.gitignore
README.md

# VS Code
.vscode/

# Visual Studio
.vs/
*.user
*.userosscache
*.sln.docstates

# Build results
**/bin/
**/obj/
**/out/

# Node modules and build outputs
**/node_modules/
**/dist/
**/build/

# OS generated files
.DS_Store
Thumbs.db

# Logs
*.log
logs/

# Database files
*.mdf
*.ldf
*.bak

# Temporary files
**/tmp/
**/temp/
```

### 3. Create `render.yaml` (Optional - for Infrastructure as Code)

```yaml
services:
  - type: web
    name: danphe-emr
    env: docker
    plan: starter
    dockerfilePath: ./Dockerfile
    envVars:
      - key: AZURE_SQL_SERVER
        value: your-azure-sql-server-name
      - key: AZURE_SQL_USER
        value: your-azure-sql-username
      - key: AZURE_SQL_PASSWORD
        value: your-azure-sql-password
      - key: ASPNETCORE_ENVIRONMENT
        value: Production
    healthCheckPath: /health
```

## 🗄️ Azure SQL Database Setup

### 1. Create Azure SQL Database
```bash
# Using Azure CLI (optional)
az sql server create \
  --name danphe-sql-server \
  --resource-group your-resource-group \
  --location eastus \
  --admin-user danphe-admin \
  --admin-password YourSecurePassword123!

az sql db create \
  --resource-group your-resource-group \
  --server danphe-sql-server \
  --name DanpheEMR_OS \
  --service-objective S0
```

### 2. Connection String Format
```
Server=tcp:your-server.database.windows.net,1433;Initial Catalog=DanpheEMR_OS;Persist Security Info=False;User ID=username;Password=password;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;
```

### 3. Required Databases
You'll need to create these databases in Azure:
- `DanpheEMR_OS` (main database)
- `DanpheAdmin` (admin database)
- `DanpheAudit` (audit database - optional)

### 4. Firewall Configuration
- Add Render's IP ranges to Azure SQL firewall
- Or enable "Allow Azure services" for simplicity

## 📊 Database Migration Guide

### 1. Create Azure SQL Databases
Using Azure Portal or Azure CLI:

```bash
# Create resource group (if needed)
az group create --name danphe-rg --location eastus

# Create SQL Server
az sql server create \
  --name danphe-sql-server-001 \
  --resource-group danphe-rg \
  --location eastus \
  --admin-user danphe-admin \
  --admin-password 'YourSecurePassword123!'

# Create databases
az sql db create --resource-group danphe-rg --server danphe-sql-server-001 --name DanpheEMR_OS --service-objective S0
az sql db create --resource-group danphe-rg --server danphe-sql-server-001 --name DanpheAdmin --service-objective S0
az sql db create --resource-group danphe-rg --server danphe-sql-server-001 --name DanpheAudit --service-objective S0

# Configure firewall (allow all Azure services)
az sql server firewall-rule create \
  --resource-group danphe-rg \
  --server danphe-sql-server-001 \
  --name AllowAllAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0
```

### 2. Upload Your Database Scripts
Since your setup guide mentions these files from the `Database` folder:
- `DanpheAdmin_CompleteDB.sql`
- `DanpheEMR_OS.rar` (extract the .bak file)
- `Increamental_DBScript.sql`

#### Option A: Using SQL Server Management Studio (SSMS)
1. Connect to your Azure SQL Server
2. Run `DanpheAdmin_CompleteDB.sql` on the `DanpheAdmin` database
3. For the main database, you'll need to convert the .bak file to SQL scripts since Azure SQL doesn't support .bak restores

#### Option B: Using Azure Data Migration Assistant
1. Download Azure Data Migration Assistant
2. Create migration project
3. Connect to your local SQL Server and Azure SQL
4. Migrate schema and data

#### Option C: Using SqlPackage (Recommended)
```bash
# Export from local SQL Server to .bacpac
sqlpackage /Action:Export /SourceServerName:localhost /SourceDatabaseName:DanpheEMR_OS /TargetFile:DanpheEMR_OS.bacpac

# Import to Azure SQL
sqlpackage /Action:Import /SourceFile:DanpheEMR_OS.bacpac /TargetServerName:danphe-sql-server-001.database.windows.net /TargetDatabaseName:DanpheEMR_OS /TargetUser:danphe-admin /TargetPassword:YourSecurePassword123!
```

### 3. Connection String Examples
```csharp
// Your final connection strings will look like:
"DefaultConnection": "Server=tcp:danphe-sql-server-001.database.windows.net,1433;Initial Catalog=DanpheEMR_OS;Persist Security Info=False;User ID=danphe-admin;Password=YourSecurePassword123!;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
```

### 4. Cost Optimization Tips
```bash
# Start with Basic tier for development
az sql db update --resource-group danphe-rg --server danphe-sql-server-001 --name DanpheEMR_OS --service-objective Basic

# Scale up for production
az sql db update --resource-group danphe-rg --server danphe-sql-server-001 --name DanpheEMR_OS --service-objective S1
```

## 🚀 Deployment Steps

### 1. Prepare Your Repository
```bash
# Ensure your project structure looks like this:
hospital-management-emr/
├── Dockerfile
├── .dockerignore
├── appsettings.Production.json
├── render.yaml
├── Code/
│   ├── Solutions/
│   │   ├── DanpheEMR.sln
│   │   └── global.json
│   └── Websites/
│       └── DanpheEMR/
│           ├── wwwroot/
│           │   └── DanpheApp/
│           └── [other backend files]
└── Database/
```

### 2. Deploy to Render
1. **Connect Repository**: Link your GitHub repo to Render
2. **Create Web Service**: Choose "Docker" as environment
3. **Set Environment Variables**:
   ```
   AZURE_SQL_SERVER=your-server-name
   AZURE_SQL_USER=your-username
   AZURE_SQL_PASSWORD=your-password
   PORT=10000
   ```
4. **Deploy**: Render will build and deploy automatically

### 3. Post-Deployment Setup
```bash
# Monitor deployment logs
# Access your app at: https://your-app-name.onrender.com

# Check health endpoint
curl https://your-app-name.onrender.com/health
```

## 🔧 Build Optimizations

### For Faster Builds
If build times are slow, create a `.dockerignore` with more exclusions:

```dockerignore
# Additional exclusions for faster builds
**/*.md
**/*.txt
**/docs/
**/examples/
**/.git/
**/tests/
```

### Multi-Stage Build Alternative
```dockerfile
# Alternative: Lighter final image
FROM mcr.microsoft.com/dotnet/aspnet:3.1-alpine AS final
# ... rest of configuration
```

## 🐛 Troubleshooting

### Common Issues:

1. **Port Issues**: Render uses `$PORT` environment variable
   ```csharp
   // In Program.cs, ensure:
   var port = Environment.GetEnvironmentVariable("PORT") ?? "5000";
   ```

2. **File Path Issues**: Use absolute paths in production
   ```json
   "UploadFileBasePath": "/app/uploads/LabReports"
   ```

3. **Database Connection**: Verify connection strings work with external SQL Server

4. **Angular Build Fails**: Ensure Node 14 and Angular CLI 7 compatibility

### Debug Commands:
```bash
# Test locally
docker build -t danphe-emr .
docker run -p 5000:5000 -e PORT=5000 danphe-emr

# Check logs in Render dashboard
# Monitor resource usage and scaling
```

## 💡 Performance Tips

1. **Enable Response Compression** in Startup.cs
2. **Use CDN** for static Angular assets
3. **Database Connection Pooling** for better performance
4. **Health Checks** for reliability monitoring

This setup will give you a production-ready deployment on Render with proper separation of concerns and scalability considerations.