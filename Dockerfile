# InterSystems IRIS Community(AI Hub EAP)ベース。
# ローカルに docker load 済みの EAP イメージ名に合わせて IMAGE を上書きしてください。
ARG IMAGE=docker.iscinternal.com/docker-intersystems/intersystems/iris-community:2026.3.0AI.136.0
FROM $IMAGE

WORKDIR /home/irisowner/dev

ARG NAMESPACE="DEMO"

## Embedded Python 環境
ENV IRISUSERNAME "_SYSTEM"
ENV IRISPASSWORD "SYS"
ENV IRISNAMESPACE $NAMESPACE
ENV PYTHON_PATH=/usr/irissys/bin/
ENV PYTHONPATH="/usr/irissys/lib/python"
ENV PATH "/usr/irissys/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/irisowner/bin"

COPY requirements.txt /home/irisowner/dev/requirements.txt
COPY merge.cpf /home/irisowner/dev/merge.cpf

## Python 依存(MCP / AI Hub ツール用)を IRIS 管理の Python ディレクトリへ導入
RUN python3 -m venv "/home/irisowner/.venvs/mcp-tools" && \
    "/home/irisowner/.venvs/mcp-tools/bin/python" -m pip install -r /home/irisowner/dev/requirements.txt --break-system-packages --target /usr/irissys/mgr/python && \
    "/home/irisowner/.venvs/mcp-tools/bin/python" -m pip install typing-extensions --upgrade --break-system-packages --target /usr/irissys/mgr/python

## ビルド時プロビジョニング: CPF マージ(名前空間作成)+ iris.script(ZPM 導入・初期設定)
RUN --mount=type=bind,src=.,dst=. \
    iris start IRIS && \
    iris merge IRIS /home/irisowner/dev/merge.cpf && \
    iris session IRIS < iris.script && \
    iris stop IRIS quietly
