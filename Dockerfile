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