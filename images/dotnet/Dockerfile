# .NET SDK from Microsoft's Debian package repository. NuGet packages and
# global tools go to the home.
FROM clod
USER root
RUN curl -fsSL https://packages.microsoft.com/config/debian/13/packages-microsoft-prod.deb -o /tmp/ms.deb \
    && dpkg -i /tmp/ms.deb && rm /tmp/ms.deb \
    && apt-get update \
    && apt-get install -y dotnet-sdk-10.0
USER claude
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV PATH="$PATH:/home/claude/.dotnet/tools"
