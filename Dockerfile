FROM jupyter/base-notebook:latest
FROM nvcr.io/nvidia/pytorch:20.12-py3

USER root
ENV DEBIAN_FRONTEND=noninteractive
RUN LF_REPO="http://download.opensuse.org/repositories/home:/Provessor/xUbuntu_20.04" \
 && echo "deb $LF_REPO/ /" >> /etc/apt/sources.list.d/home:Provessor.list \
 && wget -qO - $LF_REPO/Release.key | apt-key add -
RUN apt-get -qq update && apt-get -qq dist-upgrade \
 && apt-get -qq install --no-install-recommends \
        wget bzip2 ca-certificates sudo locales fonts-liberation run-one \
        nvtop htop openssh-server net-tools ffmpeg libsm6 libxext6 zsh neovim lf \
 && apt-get -qq clean && rm -rf /var/lib/apt/lists/*
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen && mkdir -p /var/run/sshd \
 && ln -fs /usr/share/zoneinfo/Asia/Taipei /etc/localtime && dpkg-reconfigure -f noninteractive tzdata

ARG nb_user=jovyan lang=en_US.UTF-8 cd=/opt/conda ulb=/usr/local/bin
ENV CONDA_DIR=$cd PATH=$cd/bin:$PATH \
    LANG=$lang LANGUAGE=$lang LC_ALL=$lang \
    NB_USER=$nb_user NB_UID=1000 NB_GID=100 HOME=/home/$nb_user
COPY --from=0 $ulb/fix-permissions $ulb/
RUN chmod a+rx $ulb/fix-permissions
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su \
 && sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers \
 && sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers \
 && useradd -m -s /bin/bash -N -u $NB_UID $NB_USER \
 && mkdir -p $cd \
 && chown $NB_USER:$NB_GID $cd \
 && chmod g+w /etc/passwd \
 && fix-permissions $HOME && fix-permissions $cd
USER $NB_UID
RUN mkdir $HOME/work && fix-permissions $HOME

USER root
WORKDIR $HOME
RUN conda update --all -yqc conda-forge \
 && conda install -yqc conda-forge notebook jupyterhub jupyterlab tini=0.18.0 nodejs=15.3.0 gdcm \
 && conda list tini | grep tini | tr -s ' ' | cut -d ' ' -f 1,2 >> $cd/conda-meta/pinned \
 && conda clean --all -yf \
 && jupyter labextension uninstall jupyterlab_tensorboard jupyterlab-jupytext \
 && sed -in '/jupyter_tensorboard/ d' $cd/etc/jupyter/jupyter_notebook_config.json \
 && npm cache clean --force \
 && jupyter notebook --generate-config \
 && jupyter lab clean \
 && rm -rf $HOME/.cache/yarn \
 && fix-permissions $HOME && fix-permissions $cd

USER $NB_UID
COPY requirements.txt $HOME
RUN pip list --format=freeze | grep tensorboard | xargs pip uninstall -yq \
 && pip install -Uq --no-cache-dir -r requirements.txt && rm -f requirements.txt \
 && pip uninstall -yq pillow pillow-simd && pip install -Uq --no-cache-dir pillow-simd

USER root
RUN jupyter server extension enable --sys-prefix jupyter_server_proxy
RUN wget -q "https://github.com/sharkdp/vivid/releases/download/v0.6.0/vivid_0.6.0_amd64.deb" \
 && dpkg -i vivid_0.6.0_amd64.deb && rm -f vivid_0.6.0_amd64.deb

COPY --from=0 $ulb/start.sh $ulb/start-notebook.sh $ulb/start-singleuser.sh $ulb/
COPY --from=0 /etc/jupyter/jupyter_notebook_config.py /etc/jupyter/
RUN fix-permissions $cd && fix-permissions $HOME && fix-permissions /etc/jupyter/
ENV SHELL=/bin/zsh TERM=xterm-256color DEBIAN_FRONTEND=readline \
    JUPYTERHUB_SINGLEUSER_APP=jupyter_server.serverapp.ServerApp \
    JUPYTER_ENABLE_LAB=1
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start-notebook.sh"]
EXPOSE 8888
USER $NB_UID
