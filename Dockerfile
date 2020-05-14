FROM python:3.8-slim as builder
WORKDIR /app
ENV POETRY_VERSION 1.0.5
ADD https://raw.githubusercontent.com/python-poetry/poetry/${POETRY_VERSION}/get-poetry.py ./get-poetry.py
COPY pyproject.toml poetry.lock /app/
RUN python get-poetry.py && \
    # Docker なので virtualenvs.create する必要がない。 see: https://stackoverflow.com/questions/53835198/integrating-python-poetry-with-docker/54186818
    /root/.poetry/bin/poetry config --local virtualenvs.create false && \
    /root/.poetry/bin/poetry export -f requirements.txt -o requirements.lock && \
    pip install -r requirements.lock

FROM python:3.8-slim as runner
WORKDIR /app
COPY --from=builder /usr/local/lib/python3.8/site-packages /usr/local/lib/python3.8/site-packages
COPY . /app/

CMD ["python", "main.py"]
