<!DOCTYPE html>
<html>
<head>
	<title>Base64编码器</title>
	<meta charset="utf-8">
	<!-- 加载Tailwind CSS样式 -->
	<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.4/dist/tailwind.min.css">
</head>
<body>
	<div class="container mx-auto my-8">
		<h1 class="text-4xl font-bold mb-4">Base64编码器</h1>
		<p class="mb-4">在下方的输入框输入要编码的字符串或Base64编码后的字符串，结果将实时显示在输出框中。</p>
		<div class="mb-4">
			<textarea id="input" class="w-full h-48 p-2 border rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent" oninput="encodeOrDecode()"></textarea>
		</div>
		<div>
			<textarea id="output" class="w-full h-48 p-2 border rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent" readonly></textarea>
		</div>
	</div>

	<!-- 加载Tailwind CSS脚本 -->
	<script src="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.4/dist/tailwind.min.js"></script>
	<script>
		function encodeOrDecode() {
			var input = document.getElementById("input").value;
			var output = document.getElementById("output");
			if (isBase64(input)) {
				output.value = atob(input);
			} else {
				output.value = btoa(input);
			}
		}

		function isBase64(str) {
			try {
				return btoa(atob(str)) == str;
			} catch (err) {
				return false;
			}
		}
	</script>
</body>
</html>
