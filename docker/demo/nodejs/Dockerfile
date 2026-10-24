#
FROM oven/bun:1 AS base

#
WORKDIR .

COPY server.ts .

USER bun
EXPOSE 3000
CMD ["bun", "run", "server.ts"]
