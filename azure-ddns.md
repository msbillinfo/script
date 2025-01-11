创建 Azure 应用程序
在左侧菜单中，选择 “Azure Active Directory”。
点击 “应用注册”。
点击 “新注册”：
名称：输入应用程序名称，例如 DNSUpdaterApp。
受支持的帐户类型：选择 “仅此组织目录中的帐户”（默认）。
重定向 URI：无需设置，保持为空。
点击 “注册”。
完成后，您将看到应用的详细信息。

3. 获取 Tenant ID 和 Client ID
Tenant ID：在应用的 “概述” 页面中，记下 “目录 (租户) ID”。
Client ID：记下 “应用程序 (客户端) ID”。
4. 创建客户端密钥 (Client Secret)
在应用的左侧菜单中，选择 “证书和密码”。
点击 “新客户端密码”：
说明：输入描述，例如 DNSUpdaterSecret。
到期时间：选择合适的过期时间（推荐 12 个月或以上）。
点击 “添加”。
创建完成后，复制 “值”（这就是 Client Secret），它只会显示一次，请妥善保存。

5. 获取 Subscription ID
在 Azure Portal 中，选择 “订阅”。
找到要使用的订阅，记下对应的 订阅 ID。
6. 授予 DNS Zone 权限
在左侧菜单中，选择 “资源组”。
找到包含目标 DNS Zone 的资源组并打开。
在左侧，选择 “访问控制 (IAM)”。
点击 “添加” > “添加角色分配”。
配置权限：
角色：选择 “DNS Zone Contributor”。
分配到：选择 “用户、组或服务主体”。
选择成员：在搜索框中输入您创建的应用名称（例如 DNSUpdaterApp），并选择它。
点击 “保存”。
7. 验证权限
使用应用的凭据测试是否可以调用 Azure REST API。
在脚本中填入：
Tenant ID：上面记录的租户 ID。
Client ID：应用程序的客户端 ID。
Client Secret：刚创建的密钥值。
Subscription ID：目标订阅的 ID。
