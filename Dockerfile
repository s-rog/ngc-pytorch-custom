FROM jupyter/base-notebook:latest
FROM nvcr.io/nvidia/pytorch:20.12-py3

ARG NB_USER="jovyan"
ARG NB_UID="1000"
ARG NB_GID="100"

USER root
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get -qq update && apt-get -qq dist-upgrade && \
    apt-get -qq install --no-install-recommends wget bzip2 ca-certificates sudo locales fonts-liberation run-one && \
    apt-get -qq clean && rm -rf /var/lib/apt/lists/* && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen

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
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    mkdir -p $CONDA_DIR && \
    chown $NB_USER:$NB_GID $CONDA_DIR && \
    chmod g+w /etc/passwd && \
    fix-permissions $HOME && \
    fix-permissions $CONDA_DIR

USER $NB_UID
WORKDIR $HOME
ARG PYTHON_VERSION=default
RUN mkdir /home/$NB_USER/work && \
    fix-permissions /home/$NB_USER

USER root
RUN conda update --all -yq -c conda-forge && \
    conda install --quiet -y -c conda-forge notebook jupyterhub jupyterlab nodejs=15.3.0 tini=0.18.0 && \
    conda list tini | grep tini | tr -s ' ' | cut -d ' ' -f 1,2 >> $CONDA_DIR/conda-meta/pinned && \
    conda clean --all -f -y && \
    npm cache clean --force && \
    jupyter notebook --generate-config && \
    rm -rf $CONDA_DIR/share/jupyter/lab/staging && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER

RUN apt-get -qq update && \
    apt-get -qq install --no-install-recommends \
        nvtop htop openssh-server net-tools ffmpeg libsm6 libxext6 zsh && \
    rm -rf /var/lib/apt/lists/* && mkdir -p /var/run/sshd
RUN sed -in '/jupyter_tensorboard/ d' /opt/conda/etc/jupyter/jupyter_notebook_config.json && \
    jupyter labextension uninstall --no-build jupyterlab_tensorboard jupyterlab-jupytext
RUN conda install --quiet -y -c conda-forge \
        jupytext ipywidgets black yapf isort jupyterlab_code_formatter jupyterlab-lsp=3.2.0 jedi-language-server=0.21.0 \
        jupyter-server-proxy  gdcm && \
    conda clean --all -f -y && \
    fix-permissions $CONDA_DIR && \
    fix-permissions /home/$NB_USER
RUN jupyter labextension install  @jupyter-widgets/jupyterlab-manager @jupyterlab/server-proxy
USER $NB_UID
RUN pip list --format=freeze | grep tensorboard | xargs pip uninstall -yq && \
    pip install -Uq --no-cache-dir \
        pandas tqdm scipy scikit-learn numpy opencv-python matplotlib pydicom pyarrow h5py colorama rasterio \
        tensorboard shapely aquirdturtle_collapsible_headings && \
    pip uninstall -yq pillow pillow-simd && pip install -Uq --no-cache-dir pillow-simd

EXPOSE 8888
ENV JUPYTER_ENABLE_LAB=1
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start-notebook.sh"]
ARG DATE=1053243

COPY --from=0 /usr/local/bin/start.sh /usr/local/bin/start.sh
COPY --from=0 /usr/local/bin/start-notebook.sh /usr/local/bin/start-notebook.sh
COPY --from=0 /usr/local/bin/start-singleuser.sh /usr/local/bin/start-singleuser.sh
COPY --from=0 /etc/jupyter/jupyter_notebook_config.py /etc/jupyter/jupyter_notebook_config.py

USER root
RUN fix-permissions $CONDA_DIR && fix-permissions /home/$NB_USER && fix-permissions /etc/jupyter/
ENV JUPYTERHUB_SINGLEUSER_APP='jupyter_server.serverapp.ServerApp'
ENV SHELL="/bin/zsh" TERM="xterm-256color"
RUN jupyter server extension enable --sys-prefix jupyter_server_proxy
USER $NB_UID
