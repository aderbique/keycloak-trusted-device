# Keycloak Trusted Device Image

This repository builds and publishes a custom [Keycloak](https://github.com/keycloak/keycloak) image with support for the [Keycloak SPI Trusted Device](https://github.com/wouterh-dev/keycloak-spi-trusted-device) extension.  
It adds a configurable authentication flow that allows Keycloak to **remember trusted devices** and selectively skip MFA challenges when logging in from recognized devices.

The image is automatically published to Docker Hub:  
➡ **[Docker Hub Repository](https://hub.docker.com/repository/docker/austinderbique/keycloak-trusted-device/general)**

---

## Setting the Authentication Flow

> **Important:** Before changing authentication flows, make a full backup of your Keycloak database (e.g., dump your Postgres/MySQL). If anything goes wrong, you can restore and revert safely.

### Steps

1. **Log in to the Admin Console**  
   `https://<your-keycloak-domain>/admin`

2. **Go to Authentication → Flows**  
   - In the left sidebar, click **Authentication**.  
   - Open the **Flows** tab.

3. **Duplicate the built-in “Browser” flow**  
   - Find **Browser**.  
   - Click the **⋯ (3-dot) menu** → **Duplicate**.  
   - Name it something like **Browser with Trusted MFA**.

4. **Edit the duplicated flow to match the trusted-device design**  
   Use the table in this README as your source of truth (the **Authentication Flow Structure** section). In practice that means:
   - Keep the top-level executions (e.g., **Cookie**, **Kerberos**, **Identity Provider Redirector**) with the same requirements as shown in the table.
   - Ensure the forms subflow (often called **Forms**) contains **Username Password Form** set to **Required**.
   - Add two **subflows** under the forms subflow:
     - **Device Not Trusted** (type: **Flow**, requirement: **Conditional**)  
       Add executions inside it:
       - **Condition – user configured** → **Required**  
       - **Condition – Device Trusted** → **Required** and **Negated** (so this subflow only runs when the device is *not* trusted)  
       - **OTP Form** → **Required**  
       - **Register Trusted Device** → **Required**
     - **Device Trusted** (type: **Flow**, requirement: **Conditional**)  
       Add executions inside it:
       - **Condition – Device Trusted** → **Required**  
       - **Condition – Credential Configured** → **Required**  
       - **Allow access** → **Required**  
       - **Conditional OTP Form** → **Required** (this will only show if its internal conditions are met)
   - Make sure the **requirements** for each item match the table (Alternative/Disabled/Conditional/Required).

5. **Bind the new flow as your Browser flow**  
   - Go to **Authentication → Bindings**.  
   - Set **Browser Flow** = **Browser with Trusted MFA** (the flow you just created).  
   - Save.

6. **Test safely**  
   - Use a **non-admin test user** first.  
   - Verify that an **untrusted** device gets prompted for MFA and then offers to **Register Trusted Device**.  
   - Log in again from the same device and confirm MFA is **skipped** (or conditionally shown) when the device is recognized.

7. **Roll out**  
   - Once validated with test users, switch production traffic. Keep the database backup until you’re confident in the new flow.

---

## 📜 Authentication Flow Structure

Below is the default **Browser with Trusted MFA** flow configuration used in this image.  
This table shows each step, its type, whether it has an alias or is negated, and its requirement level.

| Step / Flow                                | Type        | Alias                        | Negated | Requirement  |
|--------------------------------------------|-------------|------------------------------|---------|--------------|
| Cookie                                     | execution   |                              |         | Alternative  |
| Kerberos                                   | execution   |                              |         | Disabled     |
| Identity Provider Redirector               | execution   |                              |         | Alternative  |
| Browser with Trusted MFA forms             | flow        |                              |         | Alternative  |
| └─ Username Password Form                  | step        |                              |         | Required     |
| Device Not Trusted                         | flow        |                              |         | Conditional  |
| ├─ Condition - user configured             | condition   | ConditionUserConfigured      |         | Required     |
| ├─ Condition - Device Trusted              | condition   | ConditionDeviceNotTrusted    | True    | Required     |
| ├─ OTP Form                                | step        |                              |         | Required     |
| └─ Register Trusted Device                 | step        | RegisterTrustedDevice        |         | Required     |
| Device Trusted                             | flow        |                              |         | Conditional  |
| ├─ Condition - Device Trusted              | condition   | ConditionDeviceTrusted       |         | Required     |
| ├─ Condition - Credential Configured       | condition   | ConditionCredentialConfigured|         | Required     |
| ├─ Allow access                            | step        |                              |         | Required     |
| └─ Conditional OTP Form                    | step        |                              |         | Required     |

---

## 🚀 Release Schedule

The Docker image is **automatically built and published** using GitHub Actions under the following triggers:

1. **Scheduled Build**  
   - Runs **weekly on Monday at 09:00 America/Phoenix (16:00 UTC)**.  
   - Fetches the **latest Keycloak release** from the [Keycloak GitHub repository](https://github.com/keycloak/keycloak).  
   - Skips build if the version has already been published.

2. **Manual Trigger**  
   - You can run the workflow manually in GitHub Actions.  
   - Specify a `keycloak_version` to build that exact version, or leave blank to build the latest.

3. **Tag Push**  
   - Pushing a Git tag like `v26.3` will force a build for Keycloak version `26.3`.

---

## 📦 Availability

Images are pushed to Docker Hub at:  
**[austinderbique/keycloak-trusted-device](https://hub.docker.com/repository/docker/austinderbique/keycloak-trusted-device/general)**  

Tags follow the pattern:

- `<KEYCLOAK_VERSION>` → e.g., `26.3`
- `latest` → mirrors the most recently built Keycloak version

---

## 🛠 Usage

Example `docker run` command:

```bash
docker run -d \
  --name keycloak \
  -p 8080:8080 \
  austinderbique/keycloak-trusted-device:26.3
version: "3.8"
services:
  keycloak:
    image: austinderbique/keycloak-trusted-device:26.3
    ports:
      - "8080:8080"
    environment:
      - KEYCLOAK_ADMIN=admin
      - KEYCLOAK_ADMIN_PASSWORD=admin
```

Example Docker Stack:

```bash
version: "3.9"

networks:
  app-net:
    driver: overlay
    attachable: true

volumes:
  postgres_data:
    driver: local

services:
  postgres:
    image: postgres:17
    environment:
      POSTGRES_DB: keycloak
      POSTGRES_USER: keycloak_db_user
      POSTGRES_PASSWORD: somepasswordpostgres
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - app-net
    healthcheck:
      test: ["CMD", "pg_isready", "-q", "-d", "keycloak", "-U", "keycloak_db_user"]
      interval: 10s
      timeout: 45s
      retries: 10
      start_period: 20s
    deploy:
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 5

  keycloak:
    image: austinderbique/keycloak-trusted-device:26.3
    command:
      - start
      - --http-enabled=true
      - --proxy-headers=xforwarded
      - --hostname-strict=false
    environment:
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://postgres:5432/keycloak
      KC_DB_USERNAME: keycloak_db_user
      KC_DB_PASSWORD: somepasswordpostgres

      KEYCLOAK_ADMIN: keycloak_user
      KEYCLOAK_ADMIN_PASSWORD: somepasswordadmin

      KC_HOSTNAME: keycloak.example.com
      KC_HTTP_PORT: "8080"
      KC_PROXY: passthrough
    ports:
      - target: 8080
        published: 8080
        protocol: tcp
        mode: ingress
    networks:
      - app-net
    healthcheck:
      test: ["CMD-SHELL", "bash -lc '</dev/tcp/127.0.0.1/8080'"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 60s
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 5
```

## 📚 References

- **Keycloak** – [https://github.com/keycloak/keycloak](https://github.com/keycloak/keycloak)  
  The official Keycloak identity and access management project, providing the base image and authentication framework.

- **Keycloak SPI Trusted Device** – [https://github.com/wouterh-dev/keycloak-spi-trusted-device](https://github.com/wouterh-dev/keycloak-spi-trusted-device)  
  The extension enabling trusted device support in Keycloak, allowing conditional MFA prompts based on device recognition.

- **Docker Hub – austinderbique/keycloak-trusted-device** – [https://hub.docker.com/repository/docker/austinderbique/keycloak-trusted-device/general](https://hub.docker.com/repository/docker/austinderbique/keycloak-trusted-device/general)  
  The published container images for this project, built automatically from the latest compatible Keycloak release and the trusted device extension.
