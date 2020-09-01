FROM nvidia/cuda:10.2-cudnn7-devel-ubuntu18.04

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		ca-certificates \
# ERROR: no download agent available; install curl, wget, or fetch
		curl \
	; \
	rm -rf /var/lib/apt/lists/*

ENV JULIA_PATH /usr/local/julia
ENV PATH $JULIA_PATH/bin:$PATH

# https://julialang.org/juliareleases.asc
# Julia (Binary signing key) <buildbot@julialang.org>
ENV JULIA_GPG 3673DF529D9049477F76B37566E3C7DC03D6E495

# https://julialang.org/downloads/
ENV JULIA_VERSION 1.5.1

RUN mkdir ~/.gnupg && echo "disable-ipv6" >> ~/.gnupg/dirmngr.conf

RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	if ! command -v gpg > /dev/null; then \
		apt-get update; \
		apt-get install -y --no-install-recommends \
			gnupg \
			dirmngr \
		; \
		rm -rf /var/lib/apt/lists/*; \
	fi; \
	\
# https://julialang.org/downloads/#julia-command-line-version
# https://julialang-s3.julialang.org/bin/checksums/julia-1.5.1.sha256
# this "case" statement is generated via "update.sh"
	dpkgArch="$(dpkg --print-architecture)"; \
	case "${dpkgArch##*-}" in \
# amd64
		amd64) tarArch='x86_64'; dirArch='x64'; sha256='f5d37cb7fe40e3a730f721da8f7be40310f133220220949939d8f892ce2e86e3' ;; \
# arm64v8
		arm64) tarArch='aarch64'; dirArch='aarch64'; sha256='751d7b62ebbcecbc9c8ef7669b1b7e216eb9d433276fa00cfb28831eca9ee27b' ;; \
# i386
		i386) tarArch='i686'; dirArch='x86'; sha256='6b37a2bee2dd464055dfda9bb8d994e7d4dca9079a47f6818435171c086ab802' ;; \
		*) echo >&2 "error: current architecture ($dpkgArch) does not have a corresponding Julia binary release"; exit 1 ;; \
	esac; \
	\
	folder="$(echo "$JULIA_VERSION" | cut -d. -f1-2)"; \
	curl -fL -o julia.tar.gz.asc "https://julialang-s3.julialang.org/bin/linux/${dirArch}/${folder}/julia-${JULIA_VERSION}-linux-${tarArch}.tar.gz.asc"; \
	curl -fL -o julia.tar.gz     "https://julialang-s3.julialang.org/bin/linux/${dirArch}/${folder}/julia-${JULIA_VERSION}-linux-${tarArch}.tar.gz"; \
	\
	echo "${sha256} *julia.tar.gz" | sha256sum -c -; \
	\
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys "$JULIA_GPG"; \
	gpg --batch --verify julia.tar.gz.asc julia.tar.gz; \
	command -v gpgconf > /dev/null && gpgconf --kill all; \
	rm -rf "$GNUPGHOME" julia.tar.gz.asc; \
	\
	mkdir "$JULIA_PATH"; \
	tar -xzf julia.tar.gz -C "$JULIA_PATH" --strip-components 1; \
	rm julia.tar.gz; \
	\
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	\
# smoke test
	julia --version


# Julia packages
COPY install.jl /tmp/install.jl
RUN julia /tmp/install.jl && rm /tmp/install.jl


# conda
ENV CONDA_HOME /opt/conda
RUN cd /tmp && \
    curl -s https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/miniconda.sh && \
    /bin/bash /tmp/miniconda.sh -f -b -p $CONDA_HOME && \
    rm /tmp/miniconda.sh && \
    $CONDA_HOME/bin/conda config --system --append channels conda-forge && \
    $CONDA_HOME/bin/conda config --system --set auto_update_conda false && \
    $CONDA_HOME/bin/conda config --system --set show_channel_urls true && \
    $CONDA_HOME/bin/conda install --quiet --yes conda

RUN $CONDA_HOME/bin/conda install -c conda-forge jupyterlab && \
    $CONDA_HOME/bin/conda update --all --quiet --yes

RUN echo ". ${CONDA_HOME}/etc/profile.d/conda.sh" >> ~/.bashrc && \
    echo "conda activate" >> ~/.bashrc

COPY run.sh
RUN chmod +x run.sh
CMD ["./run.sh"]

