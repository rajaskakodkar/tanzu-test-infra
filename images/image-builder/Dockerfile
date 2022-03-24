FROM debian:buster

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    apt-transport-https \
    software-properties-common \
    ca-certificates \
    curl \
    gnupg2 \
    lsb-release \
    git \
    unzip \
    jq

# Add the Docker apt-repository
RUN curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg \
    | apt-key add - && \
    add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
    $(lsb_release -cs) stable"

RUN apt-get update && \
    apt-get install -y --no-install-recommends docker-ce=5:20.10.* && \
    rm -rf /var/lib/apt/lists/* && \
    sed -i 's/cgroupfs_mount$/#cgroupfs_mount\n/' /etc/init.d/docker \
    && update-alternatives --set iptables /usr/sbin/iptables-legacy \
    && update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
  unzip -q awscliv2.zip && \
  ./aws/install -i /usr/local/aws-cli -b /usr/local/bin

# Move Docker's storage location
RUN echo 'DOCKER_OPTS="${DOCKER_OPTS} --data-root=/docker-graph"' | \
    tee --append /etc/default/docker
RUN mkdir /docker-graph

COPY ["entrypoint.sh", "run.sh", "dind.sh", "/usr/local/bin/"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

