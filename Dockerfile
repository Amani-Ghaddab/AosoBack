FROM mcr.microsoft.com/dotnet/sdk:5.0-buster-slim AS build-env
WORKDIR /app

## Arguments for setting the Sonarqube Token and the Project Key
ARG SONAR_TOKEN
ARG SONAR_PRJ_KEY

## Setting the Sonarqube Organization and Uri
ENV SONAR_ORG "karlospn"
ENV SONAR_HOST "https://sonarcloud.io"

## Install Java, because the sonarscanner needs it.
RUN mkdir -p /usr/share/man/man1/
RUN apt-get install -y openjdk-11-jre

## Install sonarscanner
RUN dotnet tool install --global dotnet-sonarscanner --version 5.3.1

## Install report generator
RUN dotnet tool install --global dotnet-reportgenerator-globaltool --version 4.8.12

## Set the dotnet tools folder in the PATH env variable
ENV PATH="${PATH}:/root/.dotnet/tools"
RUN dotnet sonarscanner begin \
	/o:"$SONAR_ORG" \
	/k:"$SONAR_PRJ_KEY" \
	/d:sonar.host.url="$SONAR_HOST" \
	/d:sonar.login="$SONAR_TOKEN" \ 
	/d:sonar.coverageReportPaths="coverage/SonarQube.xml"

## Copy the applications .csproj
COPY /src/WebApp/*.csproj ./src/WebApp/

## Restore packages
RUN dotnet restore "./src/WebApp/WebApp.csproj" -s "https://api.nuget.org/v3/index.json"

## Copy everything else
COPY . ./

## Build the app
RUN dotnet build "./src/WebApp/WebApp.csproj" -c Release --no-restore
## Run dotnet test setting the output on the /coverage folder
RUN dotnet test test/WebApp.Tests/*.csproj --collect:"XPlat Code Coverage" --results-directory ./coverage

## Create the code coverage file in sonarqube format using the cobertura file generated from the dotnet test command
RUN reportgenerator "-reports:./coverage/*/coverage.cobertura.xml" "-targetdir:coverage" "-reporttypes:SonarQube"

## Publish the app
RUN dotnet publish src/WebApp/*.csproj -c Release -o /app/publish --no-build --no-restore

## Stop scanner
RUN dotnet sonarscanner end /d:sonar.login="$SONAR_TOKEN"




FROM mcr.microsoft.com/dotnet/aspnet:5.0-focal AS base
WORKDIR /app
EXPOSE 5000
ENV ASPNETCORE_URLS=http://+:5000

# Creates a non-root user with an explicit UID and adds permission to access the /app folder
# For more info, please refer to https://aka.ms/vscode-docker-dotnet-configure-containers
RUN adduser -u 5678 --disabled-password --gecos "" appuser && chown -R appuser /app
USER appuser

FROM mcr.microsoft.com/dotnet/sdk:5.0-focal AS build
WORKDIR /src
COPY ["./AosoBack/DevOpsProject.csproj", "./"]
RUN dotnet restore "DevOpsProject.csproj"
COPY . .
WORKDIR "/src/"
RUN dotnet build "AosoBack/DevOpsProject.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "AosoBack/DevOpsProject.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "DevOpsProject.dll", "--environment=Development"]