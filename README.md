# Pipenv から Poetry に移行するときに作った Dockerfile と タスクランナー

次の点を踏まえて、 Pipenv から Poetry へ移行しました。そのときの知見をここに記します。

* Pipenv はメンテナンス頻度が落ちていること
* Pipenv のライブラリ依存解決の機能が遅く、解決できなくなることが多くなること

メンテナンス頻度の懸念は、安定しており変更もほぼ必要ない状態であれば問題ありません。しかし２つ目の問題が障害になりました。

Pipenv を使っている人は感じていると思いますが、 Pipenv の lock ファイル生成は長い時間がかかります。その遅さにしびれを切らした私はしばしば --skip-lock を入れてライブラリの動作検証を行なうこともしばしばありました。これは悪癖です。しかし、耐えられないほど長い時間であることも事実でした。

Poetry は lock ファイルの生成が非常に高速です。私は趣味プロジェクトで導入してから「これはいいぞ」と仕事のプロジェクトでも導入しました。パッケージマネージャーの移行作業は思ったよりもうまくいきました。ただし、多少工夫が必要でした。

## Pipfile から pyproject.toml

まず最初にやったのは、 `poetry init` による `pyproject.toml` の生成です。実行すれば対話に答えていくだけで生成できます。デフォルトで問題ないはずです。

次に、 Pipfile の中身を適宜コピーして `poetry add hogehoge` することでした。表記に違いはほとんどないので、ただの作業でした。

めんどくさがりな私は次のような Pipfile に書かれた文字を1行に置換して `poetry add` しました。

```Pipfileの一部
mypy = "~=0.761"
pytest = "~=5.3.5"
```

を `mypy~=0.761 pytest~=5.3.5` のように整形し、 `poetry add mypy~=0.761 pytest~=5.3.5` としました。開発用パッケージは、 `poetry add --dev hogehoge` でインストール可能です。

## Poetry に対応した Dockerfile

Poetry の公式では、 `pip` によるインストールは推奨されていません。これは `poetry` が依存しているライブラリをインストールすることになるため、依存関係の解決が困難になる可能性があるからです。

そのため Dockerfile の中では、公式が推奨している `get-poetry.py` をダウンロードする手法を使います。公式の手法そのままだと、 poetry のバージョン固定ができません。常に最新版がインストールされます。回避するために、ダウンロード先を変更します。

ダウンロード先は GitHub だったので、 `master` となっているところを Git のタグで置換することができます。

```diff
- https://raw.githubusercontent.com/python-poetry/poetry/master/get-poetry.py
+ https://raw.githubusercontent.com/python-poetry/poetry/${POETRY_VERSION}/get-poetry.py
```

POETRY_VERSION という変数を変更すれば Poetry のバージョンを簡単にコントロールできます。

Poetry がライブラリをインストールするためには pyproject.toml と poetry.lock が必要なので　COPY します。 poetry は `export` コマンドで requirements.txt を生成することができます。 `-f` は出力フォーマット、 `-o` は出力先ファイル名を指しています。出力フォーマットは現状では、 `requirements.txt` にしか[対応していません](https://python-poetry.org/docs/cli/#export)。

```
$ poetry export -f requirements.txt -o requirements.lock
```

今回作成した、 Dockerfile ではマルチステージビルドを利用していますが、必要でなければ無視してください。作成した Dockerfile の全体像を次に示します。

```Dockerfile
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
```

## Pipfile にあったタスクランナーの機能が Poetry にはない

Pipenv ではタスクランナーの機能がついていました。Pipfile に記述しておけば `pipenv run test` や `pipenv run format` というように独自のスクリプトが定義できる仕組みです。
不幸にも Poetry にはその機能がありません。似たような機能はありますが、ユースケースが異なります。その詳細については次に示すリンク先を読んでください。

- https://github.com/python-poetry/poetry/pull/591#issuecomment-504762152
- https://tech.515hikaru.net/2020-02-25-poetry-scripts/

そのため、タスクランナーを別途用意する必要があります。タスクランナーを自前で作ったり、そのためだけにライブラリを導入するのは無駄が多いです。今回は、 小さなタスクランナーを Makefile とシェルスクリプトで作成しました。

Makefile にはターゲットと実行コマンドを書きます。ターゲットは .PHONY に入れてファイルと競合しないように注意してください。また、引数が必要な実行については後述する注意が必要です。

```
.PHONY: isort black test flake8 say

format: isort black

isort:
	isort -rc .

black:
	black

flake8:
	flake8 --config .flake8

test:
	pytest .
```

### Makefile で可変長変数をプロキシする

引数を受け取らないタスクランナーであれば、上述した記述で `make format` を打ち込むだけで簡単に isort と black が動作してくれます。これは非常に便利です。

しかし make の本来の用途であるビルドとは異なった使い方です。故に可変長引数の扱いが簡単ではありません。そこで、小さなシェルスクリプトで回避策を考えました。次に示します。

```
#!/bin/bash

TARGET=$1
shift
make "$TARGET" ARGS="$*"
```

これは make のラッパーです。 `./run-script test` と書けば `make test` に展開されます。 第2引数以降は `$*` を利用することでスペースを含んだ文字列として Makefile の ARGS に展開できます。

例えば可変長引数を受け取りたい次のような make ターゲットが合ったとすると、 `$(ARGS)` の部分が第2引数以降として処理されます。

```
.PHONY: say

say:
	python -m scripts.main say $(ARGS)
```

この工夫によって、 Makefile とシェルスクリプトでタスクランナーが実現できます。

## 移行を終えて

移行の方法は以上です。パッケージマネージャーの移行作業はより骨が折れるかと思いましたが、案外簡単にすみました。実作業にして1時間です(調査時間は含んでいません)。

Pipenv を使っていてずっと悩んでいた依存解決や、遅さが Poetry を選択してからまったく気にならなくなりました。
