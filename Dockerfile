# Multi-stage build for DanpheEMR on Render
# Stage 1: Build Angular application
FROM node:14-alpine AS angular-build

# Set working directory for Angular build
WORKDIR /app/frontend

# Install Angular CLI 7 globally and dependencies
RUN npm install -g @angular/cli@7 && \
    apk add --no-cache python3 make g++

# Copy Angular project files
COPY Code/Websites/DanpheEMR/wwwroot/DanpheApp/package*.json ./

# Install dependencies with legacy peer deps for Angular 7 compatibility
RUN npm install --legacy-peer-deps --production=false

# Copy Angular source code
COPY Code/Websites/DanpheEMR/wwwroot/DanpheApp/ ./

# Build Angular application
RUN ng build --prod --output-path=dist --base-href=/ --build-optimizer

# Stage 2: Build .NET Core application
FROM mcr.microsoft.com/dotnet/sdk:3.1 AS dotnet-build

WORKDIR /src

# Copy solution and project files for better caching
COPY Code/Solutions/*.sln ./
COPY Code/Solutions/global.json ./

# Find and copy all .csproj files
COPY Code/Websites/DanpheEMR/*.csproj ./DanpheEMR/

# Restore NuGet packages
RUN dotnet restore DanpheEMR/DanpheEMR.csproj

# Copy all source code
COPY Code/Websites/DanpheEMR/ ./DanpheEMR/

# Build and publish the application
RUN dotnet publish DanpheEMR/DanpheEMR.csproj \
    -c Release \
    -o /app/publish \
    --no-restore \
    --verbosity normal

# Stage 3: Final runtime image
FROM mcr.microsoft.com/dotnet/aspnet:3.1 AS final

WORKDIR /app

# Install curl for health checks
# Update package sources to use archived Debian Buster repositories
RUN sed -i 's|http://deb.debian.org/debian|http://archive.debian.org/debian|g' /etc/apt/sources.list && \
    sed -i 's|http://security.debian.org/debian-security|http://archive.debian.org/debian-security|g' /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create directories for application data
RUN mkdir -p /app/uploads/LabReports \
             /app/logs \
             /app/credentials \
             /app/wwwroot/DanpheApp

# Copy published .NET application
COPY --from=dotnet-build /app/publish ./

# Copy built Angular files to wwwroot
COPY --from=angular-build /app/frontend/dist/ ./wwwroot/DanpheApp/

# Copy database scripts (for reference)
COPY Database/ ./Database/

# Create appsettings for production
COPY appsettings.Production.json ./appsettings.Production.json

# Set environment variables
ENV ASPNETCORE_ENVIRONMENT=Production
ENV ASPNETCORE_URLS=http://+:${PORT}
ENV TZ=UTC

# Create non-root user for security
RUN groupadd -r danphe && useradd -r -g danphe danphe && \
    chown -R danphe:danphe /app && \
    chmod -R 755 /app

USER danphe

# Expose port (Render will set $PORT environment variable)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${PORT:-8080}/ || exit 1

# Start the application
ENTRYPOINT ["dotnet", "DanpheEMR.dll"]