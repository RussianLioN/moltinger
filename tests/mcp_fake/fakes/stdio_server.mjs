import { stdin, stdout } from 'node:process';

let buffer = Buffer.alloc(0);

function send(message) {
  const payload = Buffer.from(JSON.stringify(message), 'utf8');
  stdout.write(`Content-Length: ${payload.length}\r\n\r\n`);
  stdout.write(payload);
}

function handleRequest(request) {
  const { id, method, params } = request;
  switch (method) {
    case 'initialize':
      send({
        jsonrpc: '2.0',
        id,
        result: {
          protocolVersion: '2024-11-05',
          capabilities: { tools: {} },
          serverInfo: { name: 'fake-mcp-server', version: '1.0.0' },
        },
      });
      return;
    case 'notifications/initialized':
      return;
    case 'tools/list':
      send({
        jsonrpc: '2.0',
        id,
        result: {
          tools: [
            {
              name: 'echo',
              description: 'Echo a string',
              inputSchema: {
                type: 'object',
                properties: { text: { type: 'string' } },
                required: ['text'],
              },
            },
          ],
        },
      });
      return;
    case 'tools/call':
      if (params?.name === 'echo') {
        send({
          jsonrpc: '2.0',
          id,
          result: {
            content: [
              {
                type: 'text',
                text: String(params?.arguments?.text ?? ''),
              },
            ],
          },
        });
        return;
      }
      send({ jsonrpc: '2.0', id, error: { code: -32601, message: 'Unknown tool' } });
      return;
    default:
      send({ jsonrpc: '2.0', id, error: { code: -32601, message: `Unknown method: ${method}` } });
  }
}

stdin.on('data', (chunk) => {
  buffer = Buffer.concat([buffer, chunk]);

  while (true) {
    const separatorIndex = buffer.indexOf('\r\n\r\n');
    if (separatorIndex === -1) {
      return;
    }

    const header = buffer.slice(0, separatorIndex).toString('utf8');
    const match = header.match(/Content-Length:\s*(\d+)/i);
    if (!match) {
      buffer = Buffer.alloc(0);
      return;
    }

    const length = Number(match[1]);
    const messageStart = separatorIndex + 4;
    if (buffer.length < messageStart + length) {
      return;
    }

    const body = buffer.slice(messageStart, messageStart + length).toString('utf8');
    buffer = buffer.slice(messageStart + length);

    const payload = JSON.parse(body);
    handleRequest(payload);
  }
});
