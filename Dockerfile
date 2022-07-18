ARG BASE_IMAGE=cockroachdb/cockroach:latest

FROM $BASE_IMAGE

VOLUME /cockroach/cockroach-data

HEALTHCHECK --interval=5s --timeout=5s --retries=5 \
    CMD ["cockroach", "node", "status", "--insecure"]

CMD ["start-single-node", "--insecure"]
