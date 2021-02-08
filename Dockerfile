FROM jupyter/base-notebook:latest
FROM nvcr.io/nvidia/pytorch:20.12-py3

USER root
ENV DEBIAN_FRONTEND noninteractive
RUN echo 'deb http://download.opensuse.org/repositories/home:/Provessor/xUbuntu_20.04/ /' >> /etc/apt/sources.list.d/home:Provessor.list && \
    wget -qO - https://download.opensuse.org/repositories/home:Provessor/xUbuntu_20.04/Release.key | apt-key add -
RUN apt-get -qq update && apt-get -qq dist-upgrade &&\
    apt-get -qq install --no-install-recommends \
        wget bzip2 ca-certificates sudo locales fonts-liberation run-one \
        nvtop htop openssh-server net-tools ffmpeg libsm6 libxext6 zsh neovim lf &&\
    apt-get -qq clean && rm -rf /var/lib/apt/lists/*
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen &&\
    mkdir -p /var/run/sshd &&\
    ln -fs /usr/share/zoneinfo/Asia/Taipei /etc/localtime &&\
    dpkg-reconfigure -f noninteractive tzdata

ARG NB_USER="jovyan" \
    NB_UID="1000" \
    NB_GID="100"
ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    NB_USER=$NB_USER \
    NB_UID=$NB_UID \
    NB_GID=$NB_GID \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8
ENV PATH=$CONDA_DIR/bin:$PATH \
    HOME=/home/$NB_USER

COPY --from=0 /usr/local/bin/fix-permissions /usr/local/bin/fix-permissions
RUN chmod a+rx /usr/local/bin/fix-permissions

RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su &&\
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers &&\
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers &&\
    useradd -m -s /bin/bash -N -u $NB_UID $NB_USER &&\
    mkdir -p $CONDA_DIR &&\
    chown $NB_USER:$NB_GID $CONDA_DIR &&\
    chmod g+w /etc/passwd &&\
    fix-permissions $HOME && fix-permissions $CONDA_DIR

USER $NB_UID
RUN mkdir /home/$NB_USER/work && fix-permissions /home/$NB_USER

WORKDIR $HOME
USER root
RUN conda update --all -yq -c conda-forge &&\
    conda install --quiet -y -c conda-forge notebook jupyterhub jupyterlab \
        nodejs tini=0.18.0 gdcm &&\
    conda list tini | grep tini | tr -s ' ' | cut -d ' ' -f 1,2 >> $CONDA_DIR/conda-meta/pinned &&\
    conda clean --all -f -y &&\
    npm cache clean --force &&\
    jupyter notebook --generate-config &&\
    jupyter lab clean &&\
    rm -rf /home/$NB_USER/.cache/yarn &&\
    fix-permissions $CONDA_DIR && fix-permissions /home/$NB_USER
RUN jupyter labextension uninstall jupyterlab_tensorboard jupyterlab-jupytext &&\
    jupyter lab clean &&\
    sed -in '/jupyter_tensorboard/ d' /opt/conda/etc/jupyter/jupyter_notebook_config.json

USER $NB_UID
COPY requirements.txt $HOME
RUN pip list --format=freeze | grep tensorboard | xargs pip uninstall -yq &&\
    pip install -Uq --no-cache-dir -r requirements.txt &&\
    pip uninstall -yq pillow pillow-simd && pip install -Uq --no-cache-dir pillow-simd &&\
    rm -f requirements.txt
USER root
RUN jupyter server extension enable --sys-prefix jupyter_server_proxy
RUN wget -q "https://github.com/sharkdp/vivid/releases/download/v0.6.0/vivid_0.6.0_amd64.deb" &&\
    dpkg -i vivid_0.6.0_amd64.deb &&\
    rm -f vivid_0.6.0_amd64.deb

COPY --from=0 \
        /usr/local/bin/start.sh \ 
        /usr/local/bin/start-notebook.sh \ 
        /usr/local/bin/start-singleuser.sh \
    /usr/local/bin/
COPY --from=0 /etc/jupyter/jupyter_notebook_config.py /etc/jupyter/
RUN fix-permissions $CONDA_DIR && fix-permissions /home/$NB_USER && fix-permissions /etc/jupyter/
ENV JUPYTER_ENABLE_LAB=1 \
    JUPYTERHUB_SINGLEUSER_APP='jupyter_server.serverapp.ServerApp' \
    SHELL="/bin/zsh" TERM="xterm-256color"
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start-notebook.sh"]
EXPOSE 8888
USER $NB_UID
