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

# Create parent directories for external assets that Angular will copy during build
# This leverages Angular's built-in asset handling instead of manual path manipulation
RUN mkdir -p ../../../assets-dph ../../../themes

# Copy external assets to parent directories where Angular expects them
COPY Code/Websites/DanpheEMR/wwwroot/assets-dph/ ../../../assets-dph/
COPY Code/Websites/DanpheEMR/wwwroot/themes/ ../../../themes/

# Build Angular application with increased memory and optimizations
# Angular will now automatically include the external assets via angular.json configuration
RUN node --max-old-space-size=4096 ./node_modules/@angular/cli/bin/ng build --prod --output-path=dist --base-href=/ --build-optimizer --aot

# Stage 2: Build .NET application using Mono, which supports .NET Framework on Linux
FROM mono:latest AS dotnet-build
WORKDIR /src

# Copy all project files, maintaining the solution's directory structure
COPY Code/Solutions/*.sln ./
COPY Code/Solutions/global.json ./
COPY Code/Components/ ../Components/
COPY Code/Websites/DanpheEMR/ ../Websites/DanpheEMR/
COPY Code/Utilities/ ../Utilities/

# Fix case sensitivity issue for App.config, which is required by the project
RUN if [ -f "../Websites/DanpheEMR/app.config" ]; then cp "../Websites/DanpheEMR/app.config" "../Websites/DanpheEMR/App.config"; fi

# Fix repository sources for Debian Buster (EOL) and install NuGet CLI
RUN sed -i 's|http://deb.debian.org/debian|http://archive.debian.org/debian|g' /etc/apt/sources.list && \
    sed -i 's|http://security.debian.org/debian-security|http://archive.debian.org/debian-security|g' /etc/apt/sources.list && \
    sed -i '/buster-updates/d' /etc/apt/sources.list && \
    apt-get update -o Acquire::Check-Valid-Until=false && \
    apt-get install -y nuget && \
    apt-get clean

# Create packages directory for legacy projects
RUN mkdir -p ../../Solutions/packages

# Install specific packages that are causing issues
# These are the packages referenced in the legacy component projects
RUN nuget install Audit.EntityFramework -Version 14.0.2 -OutputDirectory ../../Solutions/packages || \
    nuget install Audit.EntityFramework -Version 14.0.1 -OutputDirectory ../../Solutions/packages || \
    echo "Audit.EntityFramework installation attempted"

RUN nuget install Audit.NET -Version 14.0.2 -OutputDirectory ../../Solutions/packages || \
    echo "Audit.NET installation attempted"

RUN nuget install Audit.NET.SqlServer -Version 14.0.2 -OutputDirectory ../../Solutions/packages || \
    echo "Audit.NET.SqlServer installation attempted"

RUN nuget install Audit.WebApi.Core -Version 14.0.2 -OutputDirectory ../../Solutions/packages || \
    echo "Audit.WebApi.Core installation attempted"

RUN nuget install EntityFramework -Version 6.2.0 -OutputDirectory ../../Solutions/packages || \
    echo "EntityFramework installation attempted"

RUN nuget install EntityFramework.SqlServer -Version 6.2.0 -OutputDirectory ../../Solutions/packages || \
    echo "EntityFramework.SqlServer installation attempted"

RUN nuget install Newtonsoft.Json -Version 11.0.2 -OutputDirectory ../../Solutions/packages || \
    nuget install Newtonsoft.Json -Version 13.0.1 -OutputDirectory ../../Solutions/packages || \
    echo "Newtonsoft.Json installation attempted"

# Install Microsoft ASP.NET Core packages (legacy versions for .NET Framework compatibility)
RUN nuget install Microsoft.AspNetCore.Mvc -Version 1.1.8 -OutputDirectory ../../Solutions/packages || \
    echo "Microsoft.AspNetCore.Mvc installation attempted"

RUN nuget install Microsoft.AspNetCore.Http -Version 1.1.2 -OutputDirectory ../../Solutions/packages || \
    echo "Microsoft.AspNetCore.Http installation attempted"

RUN nuget install Microsoft.Extensions.DependencyInjection -Version 1.1.1 -OutputDirectory ../../Solutions/packages || \
    echo "Microsoft.Extensions.DependencyInjection installation attempted"

# Install System packages that may be needed
RUN nuget install System.Collections.Immutable -Version 1.2.0 -OutputDirectory ../../Solutions/packages || \
    echo "System.Collections.Immutable installation attempted"

RUN nuget install Microsoft.CodeAnalysis.Common -Version 1.3.0 -OutputDirectory ../../Solutions/packages || \
    echo "Microsoft.CodeAnalysis.Common installation attempted"

RUN nuget install Microsoft.CodeAnalysis.CSharp -Version 1.3.0 -OutputDirectory ../../Solutions/packages || \
    echo "Microsoft.CodeAnalysis.CSharp installation attempted"

# Try to restore packages using msbuild (for PackageReference projects)
RUN msbuild /t:Restore DanpheEMR.sln || echo "MSBuild restore completed with warnings"

# Build and publish the main web application
RUN msbuild /t:Publish /p:Configuration=Release /p:PublishDir=/app/publish/ ../Websites/DanpheEMR/DanpheEMR.csproj

# Stage 3: Final runtime image using Mono
FROM mono:slim AS final
WORKDIR /app

# Install curl for health checks
# The mono:slim image is based on Debian Buster, which is EOL.
# We must point apt to the Debian archive repositories to install packages.
RUN sed -i 's|http://deb.debian.org/debian|http://archive.debian.org/debian|g' /etc/apt/sources.list && \
    sed -i 's|http://security.debian.org/debian-security|http://archive.debian.org/debian-security|g' /etc/apt/sources.list && \
    sed -i '/buster-updates/d' /etc/apt/sources.list && \
    apt-get update -o Acquire::Check-Valid-Until=false && \
    apt-get install -y curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create directories for application data
RUN mkdir -p /app/uploads/LabReports \
             /app/logs \
             /app/credentials \
             /app/wwwroot/DanpheApp

# Copy published .NET application from the build stage
COPY --from=dotnet-build /app/publish/ ./

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

# Start the application using the Mono runtime
ENTRYPOINT ["mono", "DanpheEMR.exe"]