ARG ubuntuVersion=jammy

FROM docker.ci.artifacts.walmart.com/wce-docker/ca-roots:latest as roots
FROM docker.ci.artifacts.walmart.com/hub-docker-release-remote/sonarsource/sonar-scanner-cli:10.0.3.1430_5.0.1 as sonar

FROM docker.ci.artifacts.walmart.com/hub-docker-release-remote/library/ubuntu:${ubuntuVersion}

COPY --from=roots /usr/local/share/ca-certificates /usr/local/share/ca-certificates
COPY --from=roots /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
RUN rm -f /etc/ssl/cert.pem && ln -s /etc/ssl/certs/ca-certificates.crt /etc/ssl/cert.pem

# Get all the ubuntu packages from "os-repo-config" folder and move them to /etc/apt/sources.list.d/ location
# This will enable apt-get to run the specified packages
RUN echo '' > /etc/apt/sources.list
COPY os-repo-config/* /etc/apt/sources.list.d/
RUN apt-get update -y

RUN apt-get install -y gnupg ca-certificates curl openjdk-17-jdk openjdk-17-jre

# apt get install python3
RUN apt-get install -y python3 python3-pip python3-setuptools

# Install Curl
RUN apt-get -y install curl

# Copy all the current directory (git repo)'s files and folders into /opt/app
COPY . /opt/app/
RUN ls -la /opt/app/*

# Make /opt/app as your work directory
WORKDIR /opt/app/

# Install all the python packages
RUN pip3 config --user set global.index-url https://pypi.ci.artifacts.walmart.com/artifactory/api/pypi/pythonhosted-pypi-release-remote/simple
RUN pip3 config --user set global.trusted-host pypi.ci.artifacts.walmart.com
RUN pip3 install -r requirements.txt

# Install playwright dependencies
RUN playwright install-deps
# Install playwright browsers at /opt/cache location
RUN PLAYWRIGHT_BROWSERS_PATH=/opt/cache python3 -m playwright install

RUN groupadd -g 10001 appGrp\
    && useradd -u 10000 -g appGrp -s /sbin/nologin -d /opt/app/ app\
    && chown -R 10000:10001 /opt/app

USER 10000

COPY --from=sonar /opt/sonar-scanner /opt/sonar-scanner
COPY sonar-project.properties /opt/sonar-scanner/conf/sonar-scanner.properties

ARG skipCodeCoverage

RUN if [ "$skipCodeCoverage" = "false" ]; then \
        PLAYWRIGHT_BROWSERS_PATH=/opt/cache xvfb-run python3 -m coverage run -m pytest -rap --junitxml coverage.xml && \
        PLAYWRIGHT_BROWSERS_PATH=/opt/cache xvfb-run python3 -m coverage xml -i; \
    fi

ARG branch
RUN echo "$branch"
RUN /opt/sonar-scanner/bin/sonar-scanner -Dproject.settings=sonar-project.properties -Dsonar.branch.name="$branch"
## Delete the sonar folders generated post sonar run (this is causing snyk issues)

ENTRYPOINT ["scripts/deploy-scripts/startup.sh"]
