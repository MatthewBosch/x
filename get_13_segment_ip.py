#!/usr/bin/env python3
"""
获取 Azure “13.” 段公共 IP 的并发脚本
Author: Xingyu Li
Created on: 2025/3/11
"""

import os
import sys
import time
import random
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed

from azure.identity import DefaultAzureCredential, CredentialUnavailableError
from azure.mgmt.network import NetworkManagementClient
from azure.core.exceptions import HttpResponseError

# —— 从环境变量读取配置 —— #
subscription_id   = os.getenv("AZ_SUBSCRIPTION_ID")
resource_group    = os.getenv("AZ_RESOURCE_GROUP")
base_ip_name      = os.getenv("AZ_IP_NAME")        # 作为前缀，例如 "temp-ip"
location          = os.getenv("AZ_LOCATION", "eastus")
CONCURRENT_COUNT  = int(os.getenv("CONCURRENT_COUNT", 5))
MAX_ROUNDS        = int(os.getenv("MAX_ROUNDS", 10))

# —— 日志配置 —— #
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)

def get_network_client():
    """获取 Azure NetworkManagementClient"""
    try:
        cred = DefaultAzureCredential()
        return NetworkManagementClient(cred, subscription_id)
    except CredentialUnavailableError as e:
        logging.error("无法获取 Azure 凭证: %s", e)
        sys.exit(1)

def create_one_ip(client, suffix):
    """
    并发创建一个 Basic + Dynamic 公共 IP
    suffix: 用于区分资源名称
    返回 (资源名称, IP 地址 or None)
    """
    name = f"{base_ip_name}-{suffix}"
    try:
        poller = client.public_ip_addresses.begin_create_or_update(
            resource_group, name,
            {
                "location": location,
                "sku": {"name": "Basic"},
                "public_ip_allocation_method": "Dynamic",
                "public_ip_address_version": "IPv4"
            }
        )
        ip_address = poller.result().ip_address
        logging.info("资源 %s 创建完成，IP=%s", name, ip_address)
        return name, ip_address
    except HttpResponseError as e:
        logging.warning("创建资源 %s 失败: %s", name, e)
        return name, None

def main():
    # 环境变量检查
    if not all([subscription_id, resource_group, base_ip_name]):
        logging.error("请先设置环境变量 AZ_SUBSCRIPTION_ID、AZ_RESOURCE_GROUP 和 AZ_IP_NAME")
        sys.exit(1)

    client = get_network_client()

    for round_no in range(1, MAX_ROUNDS + 1):
        logging.info("==== 并发尝试 第 %d 轮 / 共 %d 轮 ====", round_no, MAX_ROUNDS)

        with ThreadPoolExecutor(max_workers=CONCURRENT_COUNT) as executor:
            # 提交并发任务
            futures = {
                executor.submit(create_one_ip, client, i): i
                for i in range(CONCURRENT_COUNT)
            }

            # 收集结果
            for future in as_completed(futures):
                suffix = futures[future]
                name = f"{base_ip_name}-{suffix}"
                try:
                    _, ip = future.result()
                except Exception as e:
                    logging.warning("任务 %s 异常终止: %s", name, e)
                    continue

                if ip and ip.startswith("13."):
                    logging.info("✅ 成功获取 “13.” 段 IP：%s (资源 %s)", ip, name)
                    return

        # 本轮未命中，指数退避后进入下一轮
        backoff = min(2 ** round_no, 60)
        delay = backoff + random.random()
        logging.info("本轮未获取到目标 IP，等待 %.1f 秒后继续…", delay)
        time.sleep(delay)

    logging.error("❌ 达到最大轮次 %d，仍未获取 “13.” 段 IP", MAX_ROUNDS)
    sys.exit(1)

if __name__ == "__main__":
    main()
