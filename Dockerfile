# --- Stage 1: Build & install production dependencies ---
FROM node:22-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402 AS builder

# Use only the refreshed OS trust store while Node's bundled-CA fix is pending.
# apk verifies the signed repository metadata/packages; fail on an old mirror.
RUN apk add --no-cache --upgrade 'ca-certificates>=20261020-r0' 'ca-certificates-bundle>=20261020-r0' \
    && update-ca-certificates
ENV NODE_OPTIONS=--use-openssl-ca
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /usr/src/app

# Copy package files
COPY package*.json ./

# Install only production dependencies
RUN npm ci --omit=dev

# Version automatique figée au build : le conteneur n'a pas git à l'exécution,
# le serveur lira version.json (chaîne de repli de server/version.js). Le glob
# .gi[t] rend la copie tolérante si le contexte de build n'a pas l'historique.
RUN apk add --no-cache git
COPY server/version.js ./server/version.js
COPY tools/gen-version.js ./tools/gen-version.js
COPY .gi[t] ./.git
RUN node tools/gen-version.js

# --- Stage 2: Final runner image ---
FROM node:22-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402

# Use only the refreshed OS trust store while Node's bundled-CA fix is pending.
# apk verifies the signed repository metadata/packages; fail on an old mirror.
RUN apk add --no-cache --upgrade 'ca-certificates>=20261020-r0' 'ca-certificates-bundle>=20261020-r0' \
    && update-ca-certificates
ENV NODE_OPTIONS=--use-openssl-ca
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

WORKDIR /usr/src/app

COPY tools/verify-public-trust.mjs ./tools/verify-public-trust.mjs

# Set non-root user for security
USER node

# Copy dependencies and application files with proper ownership
COPY --chown=node:node --from=builder /usr/src/app/node_modules ./node_modules
COPY --chown=node:node --from=builder /usr/src/app/version.json ./version.json
COPY --chown=node:node package*.json ./
COPY --chown=node:node client/ ./client/
COPY --chown=node:node content/ ./content/
COPY --chown=node:node server/ ./server/
COPY --chown=node:node shared/ ./shared/

# Create database directory with proper ownership under root, then revert to node user
USER root
RUN mkdir -p /data && chown -R node:node /data
USER node

# Expose port and configure environment
ENV PORT=8080
ENV T4C_DB=/data/game.db
ENV NODE_ENV=production

EXPOSE 8080

# Lance node directement (pas via npm) : npm en PID 1 relaie mal les signaux,
# or l'arrêt gracieux (décompte 45 s + sauvegarde) repose sur SIGTERM/SIGINT.
CMD ["node", "server/index.js"]
