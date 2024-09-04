async function handleRequest(request) {
  const urlObj = new URL(request.url)
  let url = urlObj.href.replace(urlObj.origin+'/', '').trim()
  if (0!==url.indexOf('https://') && 0===url.indexOf('https:')) {
    url = url.replace('https:/', 'https://')
  } else if (0!==url.indexOf('http://') && 0===url.indexOf('http:')) {
    url = url.replace('http:/', 'http://')
  }
  const response = await fetch(url, {
    headers: request.headers,
    body: request.body,
    method: request.method
  })
  let respHeaders = {}
  response.headers.forEach((value, key)=>respHeaders[key] = value)
  respHeaders['Access-Control-Allow-Origin'] = '*'
  return new Response( await response.blob() , {
    headers: respHeaders,
    status: response.status
  });
}
addEventListener('fetch', event => {
  return event.respondWith(handleRequest(event.request))
})
