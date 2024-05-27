FROM alpine:latest

LABEL "com.github.actions.name"="Terraform Actions"
LABEL "com.github.actions.description"="Running Terraform commands (fmt, init, plan, apply, validate)"
LABEL "com.github.actions.icon"="terminal"
LABEL "com.github.actions.color"="blue"


# Install all dependencies for runing actions: git, bash, curl, jq, unzip, y tfenv
RUN apk update && \
    apk add --no-cache \
    bash \
    git \
    curl \
    jq \
    unzip

RUN git clone https://github.com/tfutils/tfenv.git ~/.tfenv && \
    ln -s ~/.tfenv/bin/* /usr/local/bin

# Set the working directory
WORKDIR /app

# Copy the script into the container
COPY entrypoint.sh .

# Ensure the script is executable
RUN chmod +x entrypoint.sh

RUN pwd

# Run the script
ENTRYPOINT ["/app/entrypoint.sh"]
