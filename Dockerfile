FROM nvcr.io/nvidia/pytorch:21.02-py3
ARG lang=en_US.UTF-8 cd=/opt/conda ulb=/usr/local/bin etcj=/etc/jupyter
# clean ngc image
RUN pip list --format=freeze | grep 'tensorboard\|jupy\|^nb' \
  | xargs pip uninstall -yq notebook \
 && sed -in '/jupyter_tensorboard/ d' $cd$etcj/jupyter_notebook_config.json
# apt
RUN export DEBIAN_FRONTEND=noninteractive && apt-get -qq update \
 && apt-get -qq dist-upgrade && apt-get -qq install --no-install-recommends \
    sudo locales fonts-liberation run-one zsh neovim bat fd-find htop \
    openssh-server net-tools ffmpeg libsm6 libxext6 \
    cmake libncurses5-dev libncursesw5-dev \
 && apt-get -qq clean && rm -rf /var/lib/apt/lists/* \
 && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen \
 && ln -fs /usr/share/zoneinfo/Asia/Taipei /etc/localtime \
 && dpkg-reconfigure -f noninteractive tzdata \
 && mkdir -p /var/run/sshd
# dpkg
RUN ver=0.6.0 && deb=vivid_$ver\_amd64.deb \
 && wget -q https://github.com/sharkdp/vivid/releases/download/v$ver/$deb \
 && dpkg -i $deb && rm -f $deb
# nvtop
RUN git clone https://github.com/Syllo/nvtop.git && mkdir -p nvtop/build \
 && cd nvtop/build && cmake .. && make && make install && rm -rf nvtop
# user and other setup
ENV CONDA_DIR=$cd LANG=$lang LANGUAGE=$lang LC_ALL=$lang \
    NB_USER=jovyan NB_UID=1000 NB_GID=100 HOME=/home/jovyan \
    PATH=$HOME/.local/bin:$PATH
WORKDIR $ulb
RUN url=https://raw.githubusercontent.com/jupyter/docker-stacks/master/base-notebook \
 && wget -q $url/fix-permissions && wget -q $url/start.sh \
 && wget -q $url/start-notebook.sh && wget -q $url/start-singleuser.sh \
 && wget -q $url/jupyter_notebook_config.py -P $etcj \
 && chmod a+rx fix-permissions start*.sh
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su \
 && sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers \
 && sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers \
 && useradd -l -m -s /bin/zsh -N -u $NB_UID $NB_USER \
 && chown $NB_USER:$NB_GID $cd && chmod g+w /etc/passwd && fix-permissions $HOME
WORKDIR $HOME
# conda
RUN conda update --all -yq && conda install -yqc conda-forge \
    tini=0.18.0 notebook=6.3.0 jupyterhub=1.3.0 jupyterlab=3.0.14 nodejs=15.14.0 gdcm \
 && conda list tini | grep tini | tr -s ' ' | cut -d ' ' -f 1,2 >> $cd/conda-meta/pinned \
 && conda clean --all -yf \
 && jupyter labextension uninstall jupyterlab_tensorboard jupyterlab-jupytext \
 && jupyter notebook --generate-config && jupyter lab clean \
 && npm cache clean --force && rm -rf $HOME/.cache/yarn
# pip
RUN pip install --no-cache-dir -Uqr jupyter-server-proxy \
 && jupyter server extension enable --sys-prefix jupyter_server_proxy
COPY requirements.txt .
RUN pip install --no-cache-dir -Uqr requirements.txt && rm -f requirements.txt
# finalize
RUN sed -re "s/c.NotebookApp/c.ServerApp/g" \
    $etcj/jupyter_notebook_config.py > $etcj/jupyter_server_config.py \
 && fix-permissions $HOME $etcj
ENV SHELL=/bin/zsh TERM=xterm-256color JUPYTER_ENABLE_LAB=1 \
    JUPYTERHUB_SINGLEUSER_APP=jupyter_server.serverapp.ServerApp
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start-notebook.sh"]
EXPOSE 8888
USER $NB_UID
