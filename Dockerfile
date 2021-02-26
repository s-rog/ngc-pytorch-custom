FROM nvcr.io/nvidia/pytorch:20.12-py3
ARG lang=en_US.UTF-8 cd=/opt/conda ulb=/usr/local/bin etcj=/etc/jupyter

RUN pip list --format=freeze | grep 'tensorboard\|jupyter\|^nb' \
  | xargs pip uninstall -yq notebook \
 && sed -in '/jupyter_tensorboard/ d' $cd$etcj/jupyter_notebook_config.json \
 && rm -f $cd$etcj/jupyter_notebook_config.jsonn

RUN url=http://download.opensuse.org/repositories/home:/Provessor/xUbuntu_20.04 \
 && echo "deb $url/ /" >> /etc/apt/sources.list.d/home:Provessor.list \
 && wget -qO - $url/Release.key | apt-key add -
RUN export DEBIAN_FRONTEND=noninteractive && apt-get -qq update \
 && apt-get -qq dist-upgrade && apt-get -qq install --no-install-recommends \
    sudo locales fonts-liberation run-one zsh neovim lf bat fd-find \
    nvtop htop openssh-server net-tools ffmpeg libsm6 libxext6 \
 && apt-get -qq clean && rm -rf /var/lib/apt/lists/* \
 && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen \
 && ln -fs /usr/share/zoneinfo/Asia/Taipei /etc/localtime \
 && dpkg-reconfigure -f noninteractive tzdata \
 && mkdir -p /var/run/sshd

RUN ver=0.6.0 && deb=vivid_$ver\_amd64.deb \
 && wget -q https://github.com/sharkdp/vivid/releases/download/v$ver/$deb \
 && dpkg -i $deb && rm -f $deb

ENV CONDA_DIR=$cd LANG=$lang LANGUAGE=$lang LC_ALL=$lang \
    NB_USER=jovyan NB_UID=1000 NB_GID=100 HOME=/home/jovyan
RUN url=https://raw.githubusercontent.com/jupyter/docker-stacks/master/base-notebook \
 && wget -q $url/fix-permissions -P $ulb \
 && wget -q $url/start.sh -P $ulb \
 && wget -q $url/start-notebook.sh -P $ulb \
 && wget -q $url/start-singleuser.sh -P $ulb \
 && wget -q $url/jupyter_notebook_config.py -P $etcj \
 && chmod a+rx $ulb/fix-permissions $ulb/start*.sh
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su \
 && sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers \
 && sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers \
 && useradd -m -s /bin/zsh -N -u $NB_UID $NB_USER \
 && chown $NB_USER:$NB_GID $cd \
 && chmod g+w /etc/passwd \
 && fix-permissions $HOME
WORKDIR $HOME

RUN conda update --all -yq && conda install -yqc conda-forge \
 tini=0.18.0 notebook=6.2.0 jupyterhub=1.3.0 jupyterlab=3.0.9 nodejs=15.10.0 gdcm \
 && conda list tini | grep tini | tr -s ' ' | cut -d ' ' -f 1,2 >> $cd/conda-meta/pinned \
 && conda clean --all -yf \
 && jupyter labextension uninstall jupyterlab_tensorboard jupyterlab-jupytext \
 && npm cache clean --force \
 && jupyter notebook --generate-config \
 && jupyter lab clean \
 && rm -rf $HOME/.cache/yarn

COPY requirements.txt $HOME
RUN pip install --no-cache-dir -Uqr requirements.txt && rm -f requirements.txt \
 && pip uninstall -yq pillow pillow-simd && pip install --no-cache-dir -Uq pillow-simd \
 && jupyter server extension enable --sys-prefix jupyter_server_proxy

RUN sed -re "s/c.NotebookApp/c.ServerApp/g" \
    $etcj/jupyter_notebook_config.py > $etcj/jupyter_server_config.py \
 && fix-permissions $HOME $etcj
ENV SHELL=/bin/zsh TERM=xterm-256color JUPYTER_ENABLE_LAB=1 \
    JUPYTERHUB_SINGLEUSER_APP=jupyter_server.serverapp.ServerApp
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start-notebook.sh"]
EXPOSE 8888
USER $NB_UID
