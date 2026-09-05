# k3s learning cluster

Учебный проект для разворачивания небольшого k3s-кластера на локальной
виртуализации libvirt/QEMU.

Проект объединяет несколько этапов:

1. Terraform создает виртуальные машины Debian и cloud-init диски.
2. `deploy.py` получает IP-адреса из Terraform outputs и временно собирает
   Ansible inventory.
3. Ansible устанавливает k3s и забирает kubeconfig на локальную машину.
4. Ansible разворачивает Kubernetes Dashboard и стек мониторинга.

Это учебная конфигурация, а не production-ready кластер. В частности,
Terraform использует статические адреса в libvirt-сети, а Dashboard получает
права `cluster-admin`.

## Требования

- Linux с установленными QEMU/KVM, libvirt и cloud-init;
- Terraform 1.x;
- Python 3.10+;
- Ansible;
- доступный локальный libvirt provider;
- базовый Debian GenericCloud image.

Путь к базовому образу задается в `terraform/main.tf` и перед запуском должен
соответствовать вашей системе.

## Подготовка

Создайте виртуальное окружение и установите Python-зависимости:

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

Установите внешнюю Ansible-роль k3s:

```bash
ansible-galaxy install -r ansible/requirements.yml -p ansible/roles
```

Скопируйте пример Terraform-переменных и замените значения на параметры своей
libvirt-сети и свой SSH public key:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Файл `terraform/terraform.tfvars` игнорируется Git и не должен публиковаться.
SSH-ключ передается в cloud-init и устанавливается пользователю каждой VM.

## Запуск

Инициализируйте Terraform:

```bash
terraform -chdir=terraform init
```

Запустите полный сценарий:

```bash
./deploy.py
```

Скрипт создает VM, ждет доступности SSH, запускает cloud-init и передает
сгенерированный inventory в `ansible/site.yml`. Для ручного запуска Ansible
используйте `ansible/inventory.example.yml` как основу, но не храните реальные
адреса и credentials в Git.

## Проверка

После завершения запуска kubeconfig сохраняется в:

```text
~/.kube/config-k3s-learning
```

Проверить кластер можно так:

```bash
KUBECONFIG="$HOME/.kube/config-k3s-learning" kubectl get nodes -o wide
KUBECONFIG="$HOME/.kube/config-k3s-learning" kubectl get pods --all-namespaces
```

Grafana публикуется через NodePort. Пароль Grafana и token Kubernetes Dashboard
выводятся Ansible-задачами после успешного развертывания. Не публикуйте этот
вывод и не используйте полученные credentials в общем доступе.

## Удаление

Удалить созданные виртуальные машины и связанные Terraform-ресурсы:

```bash
terraform -chdir=terraform destroy
```

После удаления VM при необходимости удалите локальный kubeconfig:

```bash
rm -f "$HOME/.kube/config-k3s-learning"
```

## Структура

```text
.
├── ansible/
│   ├── requirements.yml       # внешние Ansible-роли
│   ├── site.yml               # основной playbook
│   └── roles/                 # роли проекта; роль k3s ставится из Galaxy
├── terraform/
│   ├── main.tf                # VM, диски и cloud-init
│   ├── variables.tf           # входные параметры
│   └── terraform.tfvars.example
├── deploy.py                  # связка Terraform и Ansible
└── requirements.txt            # Python-зависимости
```

## Безопасность

- Не добавляйте в Git `terraform.tfvars`, Terraform state, kubeconfig, private
  keys или вывод Ansible.
- Перед публикацией заменяйте все реальные IP-адреса, имена пользователей и
  SSH keys в примерах.
- Если credentials уже попадали в старую историю Git, одной правки файлов
  недостаточно: создайте новый orphan branch или новый репозиторий и публикуйте
  только очищенное состояние.
